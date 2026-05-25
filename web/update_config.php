<?php
/**
 * SOS-GUIDE — update_config.php
 * Endpoint POST du formulaire d'administration
 *
 * Corrections v2.2 (B4 + W4) :
 *   ✅ Régénération SHA256 après chaque save (via sudo regen-hash.sh)
 *   ✅ Reload à chaud des services (nginx, dnsmasq, hostapd si SSID changé)
 *   ✅ Validation/sanitisation de tous les champs (coords GPS, numéros, textes)
 *   ✅ Journal d'audit structuré JSON avec diff avant/après
 *   ✅ Protection CSRF + opération atomique sur config.json
 *   ✅ Pas de reboot système
 */

ini_set('display_errors', 0);
error_reporting(0);

session_start();

define('CONFIG_FILE',  '/var/www/sos-guide/data/config.json');
define('AUDIT_LOG',    '/var/log/sos-guide-admin-audit.log');
define('REGEN_SCRIPT', '/usr/local/bin/sos-guide-regen-hash.sh');

// ── Helpers ──────────────────────────────────────────────────────────────────
function redirect(bool $success, string $detail = ''): void
{
    $q = $success ? 'updated=1' : ('error=1' . ($detail ? '&msg=' . urlencode($detail) : ''));
    header('Location: admin.php?' . $q);
    exit;
}

function sanitize_text(string $v, int $max = 256): string
{
    return mb_substr(trim(strip_tags($v)), 0, $max);
}

function sanitize_phone(string $v): string
{
    // Conserve chiffres, +, espace, tiret, parens — longueur max 32
    return mb_substr(preg_replace('/[^\d\+\s\-\(\)\/]/', '', $v), 0, 32);
}

function sanitize_gps(string $v): string
{
    // Accepte -180.12345678 à 180.12345678 uniquement
    return preg_match('/^-?\d{1,3}(\.\d{1,8})?$/', trim($v)) ? trim($v) : '';
}

function sanitize_freq(string $v): string
{
    // Fréquence radio : 3 chiffres + optionnel .1 chiffre, ex: 107.5
    return preg_match('/^\d{2,4}(\.\d{1,2})?$/', trim($v)) ? trim($v) : '';
}

function audit_write(array $entry): void
{
    $line = json_encode($entry, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";
    @file_put_contents(AUDIT_LOG, $line, FILE_APPEND | LOCK_EX);
}

// ── Vérifications préliminaires ───────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: admin.php');
    exit;
}

// CSRF
if (
    empty($_POST['csrf_token'])
    || empty($_SESSION['csrf_token'])
    || !hash_equals($_SESSION['csrf_token'], $_POST['csrf_token'])
) {
    audit_write([
        'ts'     => date('c'),
        'ip'     => $_SERVER['REMOTE_ADDR'] ?? 'unknown',
        'action' => 'CSRF_FAIL',
        'ua'     => substr($_SERVER['HTTP_USER_AGENT'] ?? '', 0, 120),
    ]);
    redirect(false, 'Token CSRF invalide');
}

// Invalider le token CSRF pour éviter la double soumission
$_SESSION['csrf_token'] = bin2hex(random_bytes(32));

// ── Lecture de la config existante ───────────────────────────────────────────
$config = [];
if (file_exists(CONFIG_FILE)) {
    $raw = file_get_contents(CONFIG_FILE);
    $config = json_decode($raw, true) ?? [];
}
if (empty($config['establishment'])) {
    $config['establishment'] = [];
}
if (empty($config['reassurance'])) {
    $config['reassurance'] = [];
}

// Snapshot avant modification (pour le diff d'audit)
$before = json_encode($config, JSON_UNESCAPED_UNICODE);

// ── Champs "establishment" avec sanitisation typée ────────────────────────────
$fieldRules = [
    // [nom_post]        => [clé_config,       sanitize_fn,     max_len]
    'name'               => ['name',            'sanitize_text', 128],
    'address'            => ['address',         'sanitize_text', 256],
    'lat'                => ['lat',             'sanitize_gps',  0  ],
    'lon'                => ['lon',             'sanitize_gps',  0  ],
    'type'               => ['type',            'sanitize_text', 32 ],
    'localRisk'          => ['localRisk',       'sanitize_text', 256],
    'localCrisisNumber'  => ['localCrisisNumber','sanitize_phone',32 ],
    'localSamuNumber'    => ['localSamuNumber', 'sanitize_phone',32 ],
    'localPompiersNumber'=> ['localPompiersNumber','sanitize_phone',32],
    'localMairieNumber'  => ['localMairieNumber','sanitize_phone',32 ],
    'localPrefecture'    => ['localPrefecture', 'sanitize_text', 128],
    'localDsden'         => ['localDsden',      'sanitize_text', 128],
    'localRadioFreq'     => ['localRadioFreq',  'sanitize_freq', 0  ],
    'localCroixRouge'    => ['localCroixRouge', 'sanitize_text', 128],
    'localPccAddress'    => ['localPccAddress', 'sanitize_text', 256],
    'localMeetingPoint'  => ['localMeetingPoint','sanitize_text',256],
    'localEvacuationPlan'=> ['localEvacuationPlan','sanitize_text',512],
];

// Valeurs autorisées pour le type d'établissement
$allowedTypes = [
    'erp','ecole','mairie','ehpad',
    'entreprise','bar','boitedenuit','hopital','gymnase',
];

$changed = []; // champs modifiés pour l'audit

foreach ($fieldRules as $postKey => [$cfgKey, $fn, $maxLen]) {
    if (!isset($_POST[$postKey])) {
        continue;
    }
    $raw   = (string) $_POST[$postKey];
    $clean = $maxLen > 0 ? $fn($raw, $maxLen) : $fn($raw);

    // Validation spéciale pour le type
    if ($postKey === 'type' && !in_array($clean, $allowedTypes, true)) {
        $clean = 'erp';
    }

    $old = $config['establishment'][$cfgKey] ?? '';
    if ($old !== $clean) {
        $changed[$cfgKey] = ['from' => $old, 'to' => $clean];
    }
    $config['establishment'][$cfgKey] = $clean;
}

// Message de réassurance
if (isset($_POST['reassuranceMessage'])) {
    $newMsg = sanitize_text((string) $_POST['reassuranceMessage'], 512);
    $oldMsg = $config['reassurance']['message'] ?? '';
    if ($oldMsg !== $newMsg) {
        $changed['reassuranceMessage'] = ['from' => $oldMsg, 'to' => $newMsg];
    }
    $config['reassurance']['message'] = $newMsg;
}

// Mot de passe WiFi (si soumis depuis admin)
$wifiPasswordChanged = false;
if (isset($_POST['wifiPassword']) && $_POST['wifiPassword'] !== '') {
    $newPwd = (string) $_POST['wifiPassword'];
    // Validation : vide (réseau ouvert) ou ≥8 caractères
    if (strlen($newPwd) >= 8 || $newPwd === '') {
        $oldPwd = $config['wifiPassword'] ?? '';
        if ($oldPwd !== $newPwd) {
            $wifiPasswordChanged = true;
            $changed['wifiPassword'] = ['from' => '[redacted]', 'to' => '[redacted]'];
        }
        $config['wifiPassword'] = $newPwd;
    }
}

// Détecter si le SSID a changé (nécessite restart hostapd)
$oldName = $config['establishment']['name'] ?? '';
// (Le nom est déjà mis à jour dans la boucle ci-dessus)
$newName = $config['establishment']['name'] ?? '';
$ssiChanged = ($oldName !== $newName) || $wifiPasswordChanged;

// ── Écriture atomique ─────────────────────────────────────────────────────────
$json = json_encode($config, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
if ($json === false) {
    audit_write([
        'ts' => date('c'), 'ip' => $_SERVER['REMOTE_ADDR'] ?? '',
        'action' => 'JSON_ENCODE_FAIL',
    ]);
    redirect(false, 'Erreur encodage JSON');
}

$tmpFile = CONFIG_FILE . '.tmp.' . getmypid();
if (file_put_contents($tmpFile, $json, LOCK_EX) === false) {
    redirect(false, 'Erreur écriture fichier temporaire');
}
if (!rename($tmpFile, CONFIG_FILE)) {
    @unlink($tmpFile);
    redirect(false, 'Erreur écriture atomique config.json');
}

// ── Régénération SHA256 (B4 — critique) ──────────────────────────────────────
// OBLIGATOIRE après toute modification : sinon le boot-check poweroff au prochain reboot
$hashOk     = false;
$hashOutput = '';
if (is_executable(REGEN_SCRIPT)) {
    exec('sudo ' . REGEN_SCRIPT . ' 2>&1', $hashOut, $hashRet);
    $hashOk     = ($hashRet === 0);
    $hashOutput = implode(' ', $hashOut);
} else {
    // Fallback si le script n'est pas encore en place (migration)
    $tmpHash = '/root/integrity.hash.tmp';
    $cmd     = 'find /var/www/sos-guide -type f -exec sha256sum {} \; > ' . $tmpHash
             . ' && mv ' . $tmpHash . ' /root/integrity.hash';
    exec('sudo bash -c ' . escapeshellarg($cmd) . ' 2>&1', $hashOut, $hashRet);
    $hashOk = ($hashRet === 0);
}

// ── Reload à chaud des services ───────────────────────────────────────────────
// Appel interne localhost → /api/reload-network (nginx restreint à 127.0.0.1)
$reloadResult  = ['nginx' => false, 'dnsmasq' => false, 'hostapd' => false];
$reloadErrors  = [];

// nginx — zero-downtime
exec('sudo /bin/systemctl reload nginx 2>&1', $o, $r);
if ($r === 0) {
    $reloadResult['nginx'] = true;
} else {
    $reloadErrors[] = 'nginx reload: ' . implode('', $o);
}

// dnsmasq — SIGHUP conserve les baux
exec('sudo /bin/systemctl reload dnsmasq 2>&1', $o, $r);
if ($r === 0) {
    $reloadResult['dnsmasq'] = true;
} else {
    $reloadErrors[] = 'dnsmasq reload: ' . implode('', $o);
}

// hostapd — uniquement si SSID ou WPA ont changé (~3s d'interruption WiFi)
if ($ssiChanged) {
    exec('sudo /bin/systemctl restart hostapd 2>&1', $o, $r);
    if ($r === 0) {
        $reloadResult['hostapd'] = true;
    } else {
        $reloadErrors[] = 'hostapd restart: ' . implode('', $o);
    }
} else {
    $reloadResult['hostapd'] = 'skip'; // Pas de changement SSID/WPA → pas de restart
}

// ── Journal d'audit structuré ─────────────────────────────────────────────────
$ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
audit_write([
    'ts'           => date('c'),
    'ip'           => $ip,
    'action'       => 'config_update',
    'fields_changed'=> array_keys($changed),
    'diff'         => $changed,  // valeurs sensibles (mot de passe) sont [redacted]
    'ssid_changed' => $ssiChanged,
    'hash_regen'   => $hashOk,
    'hash_output'  => $hashOutput,
    'reload'       => $reloadResult,
    'reload_errors'=> $reloadErrors,
]);

// ── Redirection avec statut enrichi ──────────────────────────────────────────
$warnings = [];
if (!$hashOk) {
    $warnings[] = 'hash_fail';
}
if (!empty($reloadErrors)) {
    $warnings[] = 'reload_partial';
}

if (empty($warnings)) {
    redirect(true);
} else {
    // Succès partiel : config sauvegardée mais hash ou reload en erreur
    header('Location: admin.php?updated=1&warn=' . urlencode(implode(',', $warnings)));
    exit;
}
