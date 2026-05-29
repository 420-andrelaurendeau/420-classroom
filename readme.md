# classroom.sh

Alternative à GitHub Classrooms utilisant le GitHub CLI (`gh`) et `git`.  
Permet de gérer des dépôts étudiants dans une organisation GitHub à partir d'un template.

## Dépendances

| Outil | Version minimale | Installation |
|-------|-----------------|--------------|
| [gh](https://cli.github.com) — GitHub CLI | 2.x | `winget install GitHub.cli` / `brew install gh` |
| [git](https://git-scm.com) | 2.x | `winget install Git.Git` / `brew install git` |
| [jq](https://jqlang.github.io/jq/) | 1.6 | `winget install jqlang.jq` / `brew install jq` |
| bash | 4.x | Inclus dans Git for Windows (Git Bash) ou WSL |

### Authentification GitHub

Avant la première utilisation, authentifier le CLI GitHub :

```bash
gh auth login
```

L'utilisateur authentifié doit avoir les droits **admin** sur l'organisation cible pour pouvoir créer des dépôts et gérer les collaborateurs.

---

## Fichier de configuration

Chaque classe est décrite par un fichier JSON. Exemple — `config_417.json` :

```json
{
    "organization": "420-andrelaurendeau",
    "template": "https://github.com/420-andrelaurendeau/420-417-AL-H26-TPF",
    "branch": "main",
    "homework_prefix": "420-417-al-h26-tp-final-",
    "teachers": [
        "didiertclaurendeau"
    ],
    "students": [
        "didiertremblay"
    ]
}
```

| Champ | Description |
|-------|-------------|
| `organization` | Organisation GitHub dans laquelle les dépôts sont créés |
| `template` | URL du dépôt template à utiliser comme base |
| `branch` | Branche de référence du template |
| `homework_prefix` | Préfixe des noms de dépôts étudiants |
| `teachers` | Liste des enseignants (le **premier** est le propriétaire des dépôts) |
| `students` | Liste des identifiants GitHub des étudiants |

---

## Utilisation

```
./classroom.sh <commande> <fichier_config> [options]
```

### `create` — Créer les dépôts étudiants

```bash
./classroom.sh create config_417.json
```

Crée un dépôt privé par étudiant dans l'organisation, à partir du template.

- Le nom du dépôt : `{homework_prefix}{username_etudiant}`
- L'étudiant reçoit l'accès **push** (lecture + écriture, sans droits admin)
- Chaque enseignant reçoit l'accès **admin**
- **Idempotent** : si un dépôt existe déjà, il est ignoré (les permissions sont tout de même réappliquées)

> **Note :** Les dépôts créés depuis un template GitHub ne sont pas des forks — ils sont indépendants du template.

---

### `report` — Rapport sur les dépôts

```bash
./classroom.sh report config_417.json
```

Affiche un tableau récapitulatif pour chaque étudiant :

| Colonne | Description |
|---------|-------------|
| Repository | Nom du dépôt |
| Commits | Nombre de commits effectués par l'étudiant (max 100) |
| Branches | Liste des branches présentes |
| URL | Lien direct vers le dépôt GitHub |

---

### `clone` — Cloner les dépôts localement

```bash
./classroom.sh clone config_417.json [répertoire]
```

Clone chaque dépôt étudiant dans le répertoire spécifié (par défaut : répertoire courant).

- Si un dépôt est déjà cloné, effectue un `git pull --ff-only` pour le mettre à jour.

```bash
# Exemple : cloner dans un sous-dossier "clones/"
./classroom.sh clone config_417.json ./clones
```

---

### `sync` — Synchroniser avec le template

```bash
./classroom.sh sync config_417.json
```

Propage les nouveaux commits du template vers chaque dépôt étudiant.

- Ajoute le template comme remote `upstream`
- Effectue un `git merge` de la branche de référence
- Pousse le résultat sur le dépôt de l'étudiant
- En cas de **conflit de merge**, le dépôt concerné est ignoré et les instructions de résolution manuelle sont affichées

---

## Exemples complets

```bash
# 1. Créer les dépôts pour tous les étudiants
./classroom.sh create config_417.json

# 2. Vérifier l'avancement de la classe
./classroom.sh report config_417.json

# 3. Cloner tous les dépôts dans un dossier dédié
./classroom.sh clone config_417.json ./travaux-etudiants

# 4. Distribuer une mise à jour du template
./classroom.sh sync config_417.json
```
