<?php
header('Content-Type: application/json');

// Sécurité : limiter l'accès aux IP locales
$remote = $_SERVER['REMOTE_ADDR'] ?? '';
$allowed = false;
if ($remote === '127.0.0.1' || $remote === '::1') {
    $allowed = true;
} elseif (strpos($remote, '10.0.0.') === 0) {
    $allowed = true;
}

if (!$allowed) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'Accès refusé']);
    exit;
}

// Récupération des données POST
$nodeName = isset($_POST['nodeName']) ? trim($_POST['nodeName']) : '';
$wifiPassword = $_POST['wifiPassword'] ?? '';
$enableLoRa = isset($_POST['enableLoRa']) && $_POST['enableLoRa'] === 'true';
$enableEthernet = isset($_POST['enableEthernet']) && $_POST['enableEthernet'] === 'true';

if (empty($nodeName)) {
    echo json_encode(['success' => false, 'message' => 'Le nom du lieu est obligatoire.']);
    exit;
}

// Charger ou créer la configuration dans /var/www/sos-guide/data/config.json
$configFile = '/var/www/sos-guide/data/config.json';
if (file_exists($configFile)) {
    $config = json_decode(file_get_contents($configFile), true);
    if (!is_array($config)) $config = ['establishment' => [], 'reassurance' => []];
} else {
    $config = ['establishment' => [], 'reassurance' => []];
    mkdir(dirname($configFile), 0755, true);
}

// Mettre à jour les champs
$config['establishment']['name'] = $nodeName;
$config['wifiPassword'] = $wifiPassword;
$config['enableLoRa'] = $enableLoRa;
$config['enableEthernet'] = $enableEthernet;
$config['installed'] = true;
$config['installDate'] = date('c');

// Sauvegarde
file_put_contents($configFile, json_encode($config, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
chown($configFile, 'www-data');
chgrp($configFile, 'www-data');

// Lancer le script de finalisation en arrière-plan
$finalizeScript = '/usr/local/bin/finalize_install.sh';
if (!file_exists($finalizeScript)) {
    // Fallback si pas encore copié
    copy('/boot/firmware/firstboot/finalize_install.sh', $finalizeScript);
    chmod($finalizeScript, 0755);
}
exec("sudo $finalizeScript > /dev/null 2>&1 &");

echo json_encode(['success' => true, 'message' => 'Configuration enregistrée, finalisation en cours...']);
