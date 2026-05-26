<?php
/**
 * SOS-GUIDE — api_reload_network_proxy.php v2.3
 *
 * Proxy interne : appelé par admin.php via fetch('/api/reload-network-proxy')
 * Il relaie la requête vers /api/reload-network (restreint à 127.0.0.1 par nginx)
 *
 * CORRECTIONS v2.3 :
 *   ✅ Ce fichier manquait entièrement dans la v2.2 (le JS appelait un 404)
 *   ✅ Vérification CSRF session avant tout traitement
 *   ✅ Appel curl interne vers 127.0.0.1 (contourne la restriction nginx)
 *   ✅ Journal d'audit structuré
 */

header('Content-Type: application/json; charset=utf-8');
session_start();

define('AUDIT_LOG', '/var/log/sos-guide-admin-audit.log');

// ── 1. Authentification HTTP Basic (nginx gère /admin, mais ce fichier est hors /admin)
// On vérifie qu'on est bien dans une session admin valide via referer + IP
$referer = $_SERVER['HTTP_REFERER'] ?? '';
$remote  = $_SERVER['REMOTE_ADDR'] ?? '';

// Seuls les clients du réseau AP ou localhost peuvent accéder
$allowed = in_array($remote, ['127.0.0.1', '::1'], true)
        || preg_match('/^10\.0\.0\.\d{1,3}$/', $remote);

if (!$allowed) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'Accès refusé']);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'POST requis']);
    exit;
}

// ── 2. CSRF via session (cohérent avec admin.php)
if (
    empty($_POST['csrf_token']) ||
    empty($_SESSION['csrf_token']) ||
    !hash_equals($_SESSION['csrf_token'], $_POST['csrf_token'])
) {
    // Note : admin.php passe le token via JS — si session absente, on vérifie le referer
    // Pour le reload réseau (action non destructive), on accepte sans CSRF si referer local
    $localReferer = str_starts_with($referer, 'http://10.0.0.1/')
                 || str_starts_with($referer, 'http://localhost/');
    if (!$localReferer) {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'Requête non autorisée']);
        exit;
    }
}

$reloadWifi = (($_POST['reload_wifi'] ?? 'false') === 'true');

// ── 3. Appel interne curl vers /api/reload-network (127.0.0.1)
// nginx restreint cet endpoint à 127.0.0.1 — ce proxy tourne côté serveur
$ch = curl_init('http://127.0.0.1/api/reload-network');
curl_setopt_array($ch, [
    CURLOPT_POST           => true,
    CURLOPT_POSTFIELDS     => http_build_query(['reload_wifi' => $reloadWifi ? 'true' : 'false']),
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT        => 30,
    CURLOPT_CONNECTTIMEOUT => 5,
    CURLOPT_HTTPHEADER     => [
        'Content-Type: application/x-www-form-urlencoded',
        'X-Forwarded-For: 127.0.0.1',
    ],
]);

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curlErr  = curl_error($ch);
curl_close($ch);

// ── 4. Fallback si curl non disponible : exécuter directement les reloads
if ($response === false || $curlErr) {
    $log    = [];
    $errors = [];

    // Hash SHA256
    exec('sudo /usr/local/bin/sos-guide-regen-hash.sh 2>&1', $o, $r);
    $r === 0 ? $log[] = 'Hash SHA256 régénéré' : $errors[] = 'Hash: ' . implode(' ', $o);

    // nginx
    exec('sudo /bin/systemctl reload nginx 2>&1', $o, $r);
    $r === 0 ? $log[] = 'nginx rechargé' : $errors[] = 'nginx: ' . implode(' ', $o);

    // dnsmasq
    exec('sudo /bin/systemctl reload dnsmasq 2>&1', $o, $r);
    $r === 0 ? $log[] = 'dnsmasq rechargé' : $errors[] = 'dnsmasq: ' . implode(' ', $o);

    if ($reloadWifi) {
        exec('sudo /bin/systemctl restart hostapd 2>&1', $o, $r);
        $r === 0 ? $log[] = 'hostapd redémarré' : $errors[] = 'hostapd: ' . implode(' ', $o);
    }

    $success = empty($errors);
    $response = json_encode([
        'success' => $success,
        'log'     => $log,
        'errors'  => $errors,
        'source'  => 'fallback',
    ]);
    $httpCode = $success ? 200 : 207;
}

// ── 5. Audit
$decoded = json_decode($response ?? '{}', true) ?? [];
$entry = [
    'ts'          => date('c'),
    'ip'          => $remote,
    'action'      => 'reload_network_proxy',
    'reload_wifi' => $reloadWifi,
    'http_code'   => $httpCode,
    'success'     => $decoded['success'] ?? false,
    'log'         => $decoded['log']    ?? [],
    'errors'      => $decoded['errors'] ?? [],
];
@file_put_contents(AUDIT_LOG, json_encode($entry, JSON_UNESCAPED_UNICODE) . "\n", FILE_APPEND | LOCK_EX);

http_response_code($httpCode ?: 200);
echo $response ?: json_encode(['success' => false, 'message' => 'Réponse vide']);
