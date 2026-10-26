# Pocket Mac

Pilotez un Mac depuis l'iPhone Duo : l'écran du Mac en haut, un clavier et un trackpad de MacBook en bas. Fonctionne sur le même Wi-Fi et à distance.

Le projet contient deux applis :

| Appli | S'installe sur | Rôle |
|---|---|---|
| **PocketMac** | l'iPhone | affiche l'écran, joue le son, dessine le clavier et le trackpad |
| **PocketMacCompagnon** | le Mac à piloter (Mac B) | filme l'écran, envoie le son, rejoue clavier et souris ; vit dans la barre des menus |

On compile les deux sur un Mac équipé de Xcode (Mac A). Le Mac B n'a pas besoin de Xcode.

## Ce qu'il faut

- Sur le Mac A : **Xcode 16 ou plus récent** (gratuit, sur le Mac App Store).
- Un compte Apple. Avec un compte gratuit, l'appli iPhone cesse de fonctionner au bout de 7 jours : il suffit alors de rebrancher l'iPhone et de relancer depuis Xcode. Avec le programme développeur (99 €/an), elle dure un an.
- Le Mac B : macOS 14 (Sonoma) ou plus récent.

## 1. Ouvrir le projet

1. Téléchargez ce dossier sur le Mac A, puis double-cliquez sur `PocketMac.xcodeproj`.
2. Xcode → Réglages → Comptes : ajoutez votre compte Apple.
3. Dans la colonne de gauche, cliquez sur le projet **PocketMac** (icône bleue), puis pour **chacune** des deux cibles (PocketMac et PocketMacCompagnon) : onglet *Signing & Capabilities* → *Team* → choisissez votre nom.

## 2. Installer l'appli sur l'iPhone

1. Branchez l'iPhone au Mac A et déverrouillez-le. Acceptez « Se fier à cet ordinateur ».
2. Sur l'iPhone : Réglages → Confidentialité et sécurité → **Mode développeur** → activé (l'iPhone redémarre).
3. En haut de Xcode, choisissez la cible **PocketMac** et votre iPhone, puis cliquez sur ▶︎.
4. Au premier lancement, l'iPhone peut bloquer l'appli : Réglages → Général → VPN et gestion de l'appareil → votre compte → *Faire confiance*.
5. Quand l'iPhone demande l'accès au **réseau local**, acceptez.

## 3. Installer l'appli compagnon sur le Mac B

1. Dans Xcode, choisissez la cible **PocketMacCompagnon** et *My Mac*, puis menu *Product* → *Archive*.
2. Dans la fenêtre qui s'ouvre : *Distribute App* → *Copy App* (ou *Custom* → *Copy App*) → enregistrez.
3. Envoyez `PocketMacCompagnon.app` au Mac B (AirDrop ou clé USB) et rangez-la dans **Applications**.
4. Sur le Mac B, ouvrez-la. Si macOS la bloque : Réglages Système → Confidentialité et sécurité → *Ouvrir quand même*.
5. Une icône d'ordinateur portable apparaît dans la barre des menus. Cliquez dessus :
   - **Enregistrement de l'écran** → *Autoriser*, cochez Pocket Mac Compagnon, puis quittez et relancez l'appli si macOS le demande.
   - **Accessibilité** → *Autoriser*, cochez Pocket Mac Compagnon.
   - Notez le **code** affiché (vous pouvez le changer).
6. Pour qu'elle démarre toute seule : Réglages Système → Général → Ouverture → ajoutez Pocket Mac Compagnon.
7. Réglages Système → Écran verrouillé : réglez « Demander le mot de passe » sur une durée longue ou *Jamais*. Un Mac verrouillé ne peut pas être déverrouillé à distance par l'appli.

L'appli empêche le Mac B de se mettre en veille tant qu'elle tourne.

## 4. Se connecter

**Sur le même Wi-Fi :** ouvrez Pocket Mac sur l'iPhone, le Mac B apparaît dans la liste. Touchez-le et saisissez le code.

**À distance (4G, autre Wi-Fi) :**
1. Installez **Tailscale** (gratuit) sur le Mac B et sur l'iPhone, et connectez-vous avec le **même compte** sur les deux.
2. Dans le menu de l'appli compagnon, une adresse `100.x.x.x (Tailscale, à distance)` apparaît.
3. Sur l'iPhone, saisissez cette adresse dans « À distance », puis le code.
4. En 4G, choisissez la qualité *Économie* dans les réglages.

Tailscale crée un tunnel chiffré entre vos appareils : rien n'est ouvert sur Internet. En plus de ça, la connexion Pocket Mac est elle-même chiffrée avec le code du Mac.

## Gestes

| Où | Geste | Effet |
|---|---|---|
| Écran | toucher | clic à cet endroit |
| Écran | appui long | clic droit |
| Écran | pincer | zoomer ; glisser pour se déplacer |
| Écran | double toucher à deux doigts | dézoomer |
| Trackpad | un doigt | déplacer le pointeur |
| Trackpad | toucher / toucher à deux doigts | clic / clic droit |
| Trackpad | deux doigts | défiler |
| Trackpad | appui long puis glisser | glisser-déposer |
| Trackpad | trois doigts gauche / droite | bureau précédent / suivant |
| Trackpad | trois doigts haut / bas | Mission Control / fenêtres de l'app |
| Clavier | ⇧ control option ⌘ | s'allument et s'appliquent à la touche suivante (⌘ puis C = copier) |
| Rangée du haut | | esc, luminosité, Mission Control, Launchpad, bureau, lecture, volume |

Réglages (roue dentée) : thème du MacBook, clavier AZERTY/QWERTY (choisissez celui du Mac B), son et vibration des touches, vitesse du pointeur, sens du défilement, qualité de l'image, son du Mac.

## Limites connues

- Seul l'écran principal du Mac B est transmis.
- Choisissez dans les réglages la même disposition de clavier que celle du Mac B.
- Le pliage de l'iPhone Duo et son écran extérieur ne sont pas encore gérés : à ajouter une fois testé sur l'appareil.
- Le son passe en qualité CD non compressée (environ 1,5 Mbit/s) : en 4G faible, coupez-le dans les réglages.
