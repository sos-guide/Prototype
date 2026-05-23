<?php
/**
 * SOS-GUIDE Admin Panel
 * Accessible via http://10.0.0.1/admin (protégé par .htpasswd)
 * Permet de modifier les informations locales affichées sur le portail.
 */

// Forcer l'affichage des erreurs en développement (à commenter en production)
// ini_set('display_errors', 1);
// error_reporting(E_ALL);

session_start();

define('CONFIG_FILE', '/var/www/sos-guide/data/config.json');
define('DATA_DIR', '/var/www/sos-guide/data/');

// Génération d'un token CSRF simple
if (empty($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

// Vérification de l'existence du fichier de configuration
if (!file_exists(CONFIG_FILE)) {
    $defaultConfig = [
        'establishment' => [
            'name' => 'Lieu Non Défini',
            'address' => 'Adresse non renseignée',
            'lat' => '',
            'lon' => '',
            'type' => 'erp',
            'localCrisisNumber' => '',
            'localRisk' => '',
            'localSamuNumber' => '',
            'localPompiersNumber' => '',
            'localMairieNumber' => '',
            'localPrefecture' => '',
            'localDsden' => '',
            'localRadioFreq' => '',
            'localCroixRouge' => '',
            'localPccAddress' => '',
            'localMeetingPoint' => '',
            'localEvacuationPlan' => ''
        ],
        'reassurance' => [
            'message' => 'Restez calme, les secours sont informés et arrivent.'
        ]
    ];
    file_put_contents(CONFIG_FILE, json_encode($defaultConfig, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
}

// Lecture de la configuration actuelle
$config = json_decode(file_get_contents(CONFIG_FILE), true);
$establishment = $config['establishment'] ?? [];
$reassurance = $config['reassurance'] ?? ['message' => ''];

// Gestion du message de succès/erreur après mise à jour
$message = '';
$messageType = '';
if (isset($_GET['updated'])) {
    $message = '✅ Configuration mise à jour avec succès.';
    $messageType = 'success';
} elseif (isset($_GET['error'])) {
    $message = '❌ Erreur lors de la mise à jour.';
    $messageType = 'error';
}

// Déterminer si une carte PNG est présente
$mapExists = file_exists('/var/www/sos-guide/img/map_location.png');

?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>⛑️ SOS-GUIDE — Administration</title>
    <style>
        :root {
            --bg: #0f172a;
            --card: #1e293b;
            --border: #334155;
            --text: #f1f5f9;
            --sub: #94a3b8;
            --accent: #3b82f6;
            --green: #22c55e;
            --red: #ef4444;
            --radius: 12px;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            background: var(--bg);
            color: var(--text);
            font-family: system-ui, -apple-system, sans-serif;
            line-height: 1.5;
            padding: 2rem 1rem;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            max-width: 900px;
            width: 100%;
            margin: 0 auto;
        }
        h1 {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            font-size: 1.8rem;
            font-weight: 700;
            margin-bottom: 0.5rem;
        }
        .subtitle {
            color: var(--sub);
            margin-bottom: 2rem;
            border-left: 4px solid var(--accent);
            padding-left: 1rem;
        }
        .card {
            background: var(--card);
            border: 1px solid var(--border);
            border-radius: var(--radius);
            padding: 1.8rem;
            margin-bottom: 1.5rem;
            box-shadow: 0 10px 25px -5px rgba(0,0,0,0.3);
        }
        .card h2 {
            font-size: 1.3rem;
            margin-bottom: 1.5rem;
            display: flex;
            align-items: center;
            gap: 0.5rem;
            border-bottom: 1px solid var(--border);
            padding-bottom: 0.75rem;
        }
        .form-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 1.2rem 1.5rem;
        }
        .form-group {
            display: flex;
            flex-direction: column;
            gap: 0.4rem;
        }
        .form-group.full-width {
            grid-column: span 2;
        }
        label {
            font-weight: 500;
            font-size: 0.85rem;
            color: var(--sub);
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        input, textarea, select {
            background: var(--bg);
            border: 1.5px solid var(--border);
            border-radius: 8px;
            padding: 0.7rem 1rem;
            color: var(--text);
            font-size: 0.95rem;
            transition: border-color 0.2s;
        }
        input:focus, textarea:focus, select:focus {
            outline: none;
            border-color: var(--accent);
        }
        textarea {
            min-height: 80px;
            resize: vertical;
        }
        .button-group {
            display: flex;
            gap: 1rem;
            margin-top: 2rem;
        }
        .btn {
            padding: 0.8rem 2rem;
            border-radius: 40px;
            font-weight: 600;
            font-size: 1rem;
            border: none;
            cursor: pointer;
            transition: all 0.15s;
            background: var(--card);
            border: 1.5px solid var(--border);
            color: var(--text);
        }
        .btn-primary {
            background: var(--accent);
            border-color: var(--accent);
            color: white;
        }
        .btn-primary:hover {
            background: #2563eb;
        }
        .btn:hover {
            transform: translateY(-2px);
        }
        .alert {
            padding: 1rem 1.5rem;
            border-radius: var(--radius);
            margin-bottom: 1.5rem;
            font-weight: 500;
        }
        .alert-success {
            background: rgba(34, 197, 94, 0.15);
            border: 1px solid var(--green);
            color: var(--green);
        }
        .alert-error {
            background: rgba(239, 68, 68, 0.15);
            border: 1px solid var(--red);
            color: var(--red);
        }
        .info-badge {
            background: var(--bg);
            border-radius: 20px;
            padding: 0.2rem 0.8rem;
            font-size: 0.8rem;
            color: var(--sub);
        }
        .map-status {
            display: flex;
            align-items: center;
            gap: 0.5rem;
            margin-top: 0.5rem;
            font-size: 0.9rem;
        }
        .map-status .dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: var(--sub);
        }
        .map-status .dot.active {
            background: var(--green);
        }
        @media (max-width: 640px) {
            .form-grid { grid-template-columns: 1fr; }
            .form-group.full-width { grid-column: span 1; }
        }
    </style>
</head>
<body>
<div class="container">
    <h1>
        <span>⛑️</span>
        SOS-GUIDE Administration
    </h1>
    <div class="subtitle">
        Configuration locale · Tous les champs sont optionnels sauf mention contraire
    </div>

    <?php if ($message): ?>
        <div class="alert alert-<?= $messageType ?>"><?= htmlspecialchars($message) ?></div>
    <?php endif; ?>

    <form method="post" action="update_config.php">
        <input type="hidden" name="csrf_token" value="<?= $_SESSION['csrf_token'] ?>">
        <div class="card">
            <h2>🏢 Informations du lieu</h2>
            <div class="form-grid">
                <div class="form-group full-width">
                    <label>Nom du lieu *</label>
                    <input type="text" name="name" value="<?= htmlspecialchars($establishment['name'] ?? '') ?>" required>
                </div>
                <div class="form-group full-width">
                    <label>Adresse complète</label>
                    <input type="text" name="address" value="<?= htmlspecialchars($establishment['address'] ?? '') ?>">
                </div>
                <div class="form-group">
                    <label>Latitude (ex: 48.8566)</label>
                    <input type="text" name="lat" value="<?= htmlspecialchars($establishment['lat'] ?? '') ?>" placeholder="optionnel">
                </div>
                <div class="form-group">
                    <label>Longitude (ex: 2.3522)</label>
                    <input type="text" name="lon" value="<?= htmlspecialchars($establishment['lon'] ?? '') ?>" placeholder="optionnel">
                </div>
                <div class="form-group">
                    <label>Type d'établissement</label>
                    <select name="type">
                        <?php
                        $types = [
                            'erp' => 'ERP (Établissement Recevant du Public)',
                            'ecole' => 'École / Établissement scolaire',
                            'mairie' => 'Mairie',
                            'ehpad' => 'EHPAD / Maison de retraite',
                            'entreprise' => 'Entreprise',
                            'bar' => 'Bar / Restaurant',
                            'boitedenuit' => 'Discothèque / Salle de concert',
                            'hopital' => 'Hôpital / Clinique',
                            'gymnase' => 'Gymnase / Salle polyvalente'
                        ];
                        $currentType = $establishment['type'] ?? 'erp';
                        foreach ($types as $value => $label) {
                            $selected = ($currentType === $value) ? 'selected' : '';
                            echo "<option value=\"$value\" $selected>$label</option>";
                        }
                        ?>
                    </select>
                </div>
                <div class="form-group">
                    <label>Risque local spécifique</label>
                    <input type="text" name="localRisk" value="<?= htmlspecialchars($establishment['localRisk'] ?? '') ?>" placeholder="ex: zone inondable, site SEVESO...">
                </div>
                <div class="form-group full-width">
                    <label>Message de réassurance</label>
                    <textarea name="reassuranceMessage"><?= htmlspecialchars($reassurance['message'] ?? 'Restez calme, les secours sont informés et arrivent.') ?></textarea>
                </div>
            </div>
        </div>

        <div class="card">
            <h2>📞 Contacts d'urgence locaux</h2>
            <div class="form-grid">
                <div class="form-group">
                    <label>📞 Cellule de crise locale</label>
                    <input type="text" name="localCrisisNumber" value="<?= htmlspecialchars($establishment['localCrisisNumber'] ?? '') ?>">
                </div>
                <div class="form-group">
                    <label>🚑 SAMU local</label>
                    <input type="text" name="localSamuNumber" value="<?= htmlspecialchars($establishment['localSamuNumber'] ?? '') ?>">
                </div>
                <div class="form-group">
                    <label>🚒 Pompiers locaux</label>
                    <input type="text" name="localPompiersNumber" value="<?= htmlspecialchars($establishment['localPompiersNumber'] ?? '') ?>">
                </div>
                <div class="form-group">
                    <label>🏛️ Mairie</label>
                    <input type="text" name="localMairieNumber" value="<?= htmlspecialchars($establishment['localMairieNumber'] ?? '') ?>">
                </div>
                <div class="form-group">
                    <label>🏛️ Préfecture</label>
                    <input type="text" name="localPrefecture" value="<?= htmlspecialchars($establishment['localPrefecture'] ?? '') ?>">
                </div>
                <div class="form-group">
                    <label>🎓 DSDEN (si école)</label>
                    <input type="text" name="localDsden" value="<?= htmlspecialchars($establishment['localDsden'] ?? '') ?>">
                </div>
                <div class="form-group">
                    <label>📻 Fréquence radio locale (MHz)</label>
                    <input type="text" name="localRadioFreq" value="<?= htmlspecialchars($establishment['localRadioFreq'] ?? '') ?>" placeholder="ex: 107.5">
                </div>
                <div class="form-group">
                    <label>🔴 Croix-Rouge locale</label>
                    <input type="text" name="localCroixRouge" value="<?= htmlspecialchars($establishment['localCroixRouge'] ?? '') ?>">
                </div>
                <div class="form-group full-width">
                    <label>📍 Adresse PCC (Poste de Commandement Communal)</label>
                    <input type="text" name="localPccAddress" value="<?= htmlspecialchars($establishment['localPccAddress'] ?? '') ?>">
                </div>
                <div class="form-group full-width">
                    <label>🚶 Point de rassemblement</label>
                    <input type="text" name="localMeetingPoint" value="<?= htmlspecialchars($establishment['localMeetingPoint'] ?? '') ?>">
                </div>
                <div class="form-group full-width">
                    <label>🗺️ Plan d'évacuation (description ou lien)</label>
                    <input type="text" name="localEvacuationPlan" value="<?= htmlspecialchars($establishment['localEvacuationPlan'] ?? '') ?>">
                </div>
            </div>
        </div>

        <div class="card">
            <h2>🖼️ Carte du lieu</h2>
            <div class="map-status">
                <span class="dot <?= $mapExists ? 'active' : '' ?>"></span>
                <span><?= $mapExists ? '✅ Carte PNG présente (map_location.png)' : '⚠️ Aucune carte PNG installée' ?></span>
            </div>
            <p style="margin-top: 1rem; font-size: 0.9rem; color: var(--sub);">
                Pour ajouter une carte personnalisée, placez une image PNG nommée <code>map_location.png</code> dans 
                <code>/var/www/sos-guide/img/</code> via SSH ou avec le script <code>sos-guide-copy-image.sh</code>.
            </p>
        </div>

        <div class="button-group">
            <button type="submit" class="btn btn-primary">💾 Enregistrer les modifications</button>
            <button type="button" class="btn" onclick="window.location.href='/'">← Retour au portail</button>
        </div>
    </form>

    <div style="margin-top: 2rem; text-align: center; font-size: 0.8rem; color: var(--sub);">
        SOS-GUIDE v2.1 · Administration locale · <a href="/admin?logout=1" style="color: var(--accent);">Déconnexion</a>
    </div>
</div>
</body>
</html>
