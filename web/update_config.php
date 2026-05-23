<?php
/**
 * SOS-GUIDE Update Config Endpoint
 * Reçoit les données du formulaire d'administration et met à jour config.json
 */

// Ne jamais afficher les erreurs en production (sinon fuite d'infos)
ini_set('display_errors', 0);
error_reporting(0);

session_start();

define('CONFIG_FILE', '/var/www/sos-guide/data/config.json');

// Fonction pour renvoyer une réponse et rediriger
function redirect($success = true, $message = '') {
    $param = $success ? 'updated=1' : 'error=1';
    header('Location: admin.php?' . $param);
    exit;
}

// Vérifier que la méthode est POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: admin.php');
    exit;
}

// Vérification du token CSRF
if (!isset($_POST['csrf_token']) || !isset($_SESSION['csrf_token']) || $_POST['csrf_token'] !== $_SESSION['csrf_token']) {
    error_log("SOS-GUIDE: tentative CSRF détectée depuis " . ($_SERVER['REMOTE_ADDR'] ?? 'inconnu'));
    redirect(false);
}

// Lire la configuration existante
if (!file_exists(CONFIG_FILE)) {
    $config = [
        'establishment' => [],
        'reassurance' => []
    ];
} else {
    $config = json_decode(file_get_contents(CONFIG_FILE), true);
    if (!is_array($config)) {
        $config = ['establishment' => [], 'reassurance' => []];
    }
}

// Mise à jour des champs "establishment"
$fields = [
    'name', 'address', 'lat', 'lon', 'type',
    'localCrisisNumber', 'localRisk', 'localSamuNumber',
    'localPompiersNumber', 'localMairieNumber', 'localPrefecture',
    'localDsden', 'localRadioFreq', 'localCroixRouge',
    'localPccAddress', 'localMeetingPoint', 'localEvacuationPlan'
];

foreach ($fields as $field) {
    if (isset($_POST[$field])) {
        $config['establishment'][$field] = trim($_POST[$field]);
    }
}

// Mise à jour du message de réassurance
if (isset($_POST['reassuranceMessage'])) {
    $config['reassurance']['message'] = trim($_POST['reassuranceMessage']);
}

// S'assurer que les tableaux existent
if (!isset($config['establishment'])) $config['establishment'] = [];
if (!isset($config['reassurance'])) $config['reassurance'] = [];

// Sauvegarde avec verrouillage atomique
$json = json_encode($config, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
if ($json === false) {
    error_log("SOS-GUIDE: Erreur encodage JSON dans update_config.php");
    redirect(false);
}

// Écrire dans un fichier temporaire puis renommer (opération atomique)
$tempFile = CONFIG_FILE . '.tmp';
if (file_put_contents($tempFile, $json, LOCK_EX) === false) {
    error_log("SOS-GUIDE: Impossible d'écrire le fichier temporaire de config");
    redirect(false);
}

if (!rename($tempFile, CONFIG_FILE)) {
    error_log("SOS-GUIDE: Impossible de renommer le fichier de config");
    redirect(false);
}

// Journaliser la modification
error_log("SOS-GUIDE: Configuration mise à jour via admin.php par " . ($_SERVER['REMOTE_ADDR'] ?? 'inconnu'));

redirect(true);
