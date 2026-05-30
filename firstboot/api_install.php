<?php
/**
 * SOS-GUIDE — api_install.php v2.3
 *
 * CORRECTIONS v2.3 :
 *   FIX BUG-19 : Race condition sur le rate-limit
 *                Lecture + incrément + écriture maintenant atomiques via flock()
 *                Un seul processus à la fois accède au fichier RATE_FILE
 */

header('Content-Type: application/json; charset=utf-8');

define('TOKEN_FILE',   '/run/sos-guide/firstboot_token');
define('PIN_FILE',     '/run/sos-guide/firstboot_pin');
define('RATE_FILE',    '/run/sos-guide/rate_limit');
define('AUDIT_LOG',    '/var/log/sos-guide-firstboot-audit.log');
define('CONFIG_FILE',  '/var/www/sos-guide/data/config.json');
define('INSTALL_DONE', '/var/lib/sos-guide/installed');
define('MAX_ATTEMPTS', 5);
define('RATE_WINDOW',  900);

function json_error(int $code, string $msg): void
{
    http_response_code($code);
    echo json_encode(['success' => false, 'message' => $msg]);
    exit;
}

function audit(string $action, array $extra = []): void
{
    $entry = array_merge([
        'ts'     => date('c'),
        'ip'     => $_SERVER['REMOTE_ADDR'] ?? 'unknown',
        'ua'     => substr($_SERVER['HTTP_USER_AGENT'] ?? '', 0, 80),
        'action' => $action,
    ], $extra);
    @file_put_contents(AUDIT_LOG,
        json_encode($entry, JSON_UNESCAPED_UNICODE) . "\n",
        FILE_APPEND | LOCK_EX);
}

// ── 1. Déjà installé ? ────────────────────────────────────────────────────────
if (file_exists(INSTALL_DONE)) {
    audit('REJECT_ALREADY_INSTALLED');
    json_error(410, 'Installation déjà effectuée. Ce endpoint est désactivé.');
}

// ── 2. POST uniquement ────────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_error(405, 'POST requis');
}

// ── 3. Whitelist IP ───────────────────────────────────────────────────────────
$remote  = $_SERVER['REMOTE_ADDR'] ?? '';
$allowed = in_array($remote, ['127.0.0.1', '::1'], true)
        || (bool) preg_match('/^10\.0\.0\.\d{1,3}$/', $remote);
if (!$allowed) {
    audit('REJECT_IP', ['ip' => $remote]);
    json_error(403, 'Accès refusé — IP non autorisée');
}

// ── 4. FIX BUG-19 : Rate-limiting ATOMIQUE via flock() ───────────────────────
// Ancien code : lecture puis écriture séparées → race condition
// Nouveau code : on ouvre le fichier en écriture, on pose un verrou exclusif
// AVANT de lire son contenu → lecture + modification + écriture sont atomiques
@mkdir(dirname(RATE_FILE), 0700, true);
$rateFh = fopen(RATE_FILE . '.lock', 'c+');
if (!$rateFh) {
    json_error(500, 'Impossible d\'accéder au fichier de rate-limit');
}
if (!flock($rateFh, LOCK_EX)) {
    fclose($rateFh);
    json_error(503, 'Service temporairement indisponible');
}

// Lecture du JSON existant sous verrou
$rateData = [];
if (file_exists(RATE_FILE)) {
    $raw = @file_get_contents(RATE_FILE);
    if ($raw !== false) {
        $rateData = json_decode($raw, true) ?? [];
    }
}

$now   = time();
$ipKey = md5($remote);

// Purger les entrées expirées
foreach ($rateData as $k => $entry) {
    if ($now - ($entry['first'] ?? 0) > RATE_WINDOW) {
        unset($rateData[$k]);
    }
}

if (!isset($rateData[$ipKey])) {
    $rateData[$ipKey] = ['first' => $now, 'count' => 0];
}
$rateData[$ipKey]['count']++;
$count = $rateData[$ipKey]['count'];

// Écriture immédiate sous verrou
file_put_contents(RATE_FILE, json_encode($rateData), LOCK_EX);

// Libérer le verrou
flock($rateFh, LOCK_UN);
fclose($rateFh);

if ($count > MAX_ATTEMPTS) {
    $remaining = RATE_WINDOW - ($now - $rateData[$ipKey]['first']);
    audit('RATE_LIMITED', ['attempts' => $count]);
    json_error(429, "Trop de tentatives. Réessayez dans " . ceil($remaining / 60) . " minute(s).");
}

// ── 5. Token CSRF one-shot ────────────────────────────────────────────────────
if (!file_exists(TOKEN_FILE)) {
    audit('REJECT_NO_TOKEN');
    json_error(503, 'Service non prêt (token absent). Patientez 30 secondes.');
}

$expectedToken  = trim(file_get_contents(TOKEN_FILE));
$submittedToken = trim($_POST['_csrf'] ?? '');

if (empty($submittedToken) || !hash_equals($expectedToken, $submittedToken)) {
    audit('REJECT_CSRF', ['submitted' => substr($submittedToken, 0, 8) . '...']);
    json_error(403, 'Token CSRF invalide ou expiré');
}

// ── 6. Vérification du PIN ────────────────────────────────────────────────────
if (!file_exists(PIN_FILE)) {
    audit('REJECT_NO_PIN');
    json_error(503, 'PIN non généré. Consultez la console physique du Raspberry Pi.');
}

$expectedPin  = trim(file_get_contents(PIN_FILE));
$submittedPin = trim($_POST['pin'] ?? '');

if (empty($submittedPin) || !hash_equals($expectedPin, $submittedPin)) {
    audit('PIN_FAIL', ['attempts' => $count]);
    $remaining_attempts = MAX_ATTEMPTS - $count;
    json_error(401, "PIN incorrect. $remaining_attempts tentative(s) restante(s) avant blocage.");
}

// ── 7. Validation des données ─────────────────────────────────────────────────
$nodeName = trim($_POST['nodeName'] ?? '');
if (empty($nodeName) || mb_strlen($nodeName) > 128) {
    json_error(400, 'Nom du lieu requis (1–128 caractères)');
}
$nodeName = preg_replace('/[^\pL\pN\s\-\.\,\'\(\)]/u', '', $nodeName);
$nodeName = mb_substr(trim($nodeName), 0, 128);
if (empty($nodeName)) {
    json_error(400, 'Nom du lieu invalide après nettoyage');
}

$wifiPassword   = $_POST['wifiPassword'] ?? '';
$enableLoRa     = isset($_POST['enableLoRa'])     && $_POST['enableLoRa']     === 'true';
$enableEthernet = isset($_POST['enableEthernet']) && $_POST['enableEthernet'] === 'true';
$wifiChannel    = intval($_POST['wifiChannel'] ?? 11);

if ($wifiChannel < 1 || $wifiChannel > 13) { $wifiChannel = 11; }
if (!empty($wifiPassword) && mb_strlen($wifiPassword) < 8) {
    json_error(400, 'Mot de passe WiFi trop court (8 caractères minimum)');
}

// ── 8. Chargement / mise à jour de config.json ────────────────────────────────
@mkdir(dirname(CONFIG_FILE), 0755, true);
$config = ['establishment' => [], 'reassurance' => ['message' => '']];
if (file_exists(CONFIG_FILE)) {
    $existing = json_decode(file_get_contents(CONFIG_FILE), true);
    if (is_array($existing)) { $config = $existing; }
}

$config['establishment']['name'] = $nodeName;
$config['wifiPassword']          = $wifiPassword;
$config['wifiChannel']           = $wifiChannel;
$config['enableLoRa']            = $enableLoRa;
$config['enableEthernet']        = $enableEthernet;
$config['installed']             = false;
$config['installDate']           = date('c');
$config['installedFrom']         = $remote;

// ── 9. Écriture atomique ──────────────────────────────────────────────────────
$json    = json_encode($config, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
$tmpFile = CONFIG_FILE . '.tmp.' . getmypid();
if (file_put_contents($tmpFile, $json, LOCK_EX) === false) {
    audit('WRITE_FAIL');
    json_error(500, 'Erreur écriture configuration');
}
if (!rename($tmpFile, CONFIG_FILE)) {
    @unlink($tmpFile);
    json_error(500, 'Erreur sauvegarde atomique');
}
@chown(CONFIG_FILE, 'www-data');
@chgrp(CONFIG_FILE, 'www-data');
@chmod(CONFIG_FILE, 0640);

// ── 10. Invalidation du token CSRF (one-shot) ─────────────────────────────────
@unlink(TOKEN_FILE);

// ── 11. Lancement de finalize_install.sh ─────────────────────────────────────
$finalizeScript = '/usr/local/bin/finalize_install.sh';
if (!file_exists($finalizeScript)) {
    foreach (['/boot/firmware/firstboot', '/boot/firstboot'] as $src) {
        if (file_exists("$src/finalize_install.sh")) {
            copy("$src/finalize_install.sh", $finalizeScript);
            chmod($finalizeScript, 0755);
            break;
        }
    }
}
$launched = false;
if (file_exists($finalizeScript) && is_executable($finalizeScript)) {
    exec("sudo $finalizeScript >> /var/log/sos-guide-install.log 2>&1 &");
    $launched = true;
} else {
    audit('FINALIZE_MISSING');
}

// ── 12. Réinitialiser le rate-limit après succès ──────────────────────────────
// Re-lire sous verrou pour ne pas écraser des changements concurrents
$rateFh2 = @fopen(RATE_FILE . '.lock', 'c+');
if ($rateFh2 && flock($rateFh2, LOCK_EX)) {
    $raw2     = @file_get_contents(RATE_FILE);
    $rateData = $raw2 ? (json_decode($raw2, true) ?? []) : [];
    unset($rateData[$ipKey]);
    file_put_contents(RATE_FILE, json_encode($rateData), LOCK_EX);
    flock($rateFh2, LOCK_UN);
    fclose($rateFh2);
}

audit('INSTALL_STARTED', [
    'node'     => $nodeName,
    'channel'  => $wifiChannel,
    'lora'     => $enableLoRa,
    'ethernet' => $enableEthernet,
    'wpa'      => !empty($wifiPassword),
    'launched' => $launched,
]);

echo json_encode([
    'success'  => true,
    'launched' => $launched,
    'message'  => $launched
        ? 'Configuration enregistrée. Finalisation en cours (sans redémarrage)...'
        : 'Configuration enregistrée. Lancer manuellement : sudo /usr/local/bin/finalize_install.sh',
    'node'     => $nodeName,
    'channel'  => $wifiChannel,
]);
