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

Chaque classe est décrite par un fichier JSON. Le script supporte deux scénarios :

### Scénario 1 : Travaux individuels par étudiant

Exemple — `config_417.json` :

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
        "didiertremblay",
        "anotherStudent"
    ]
}
```

**Comportement :** Un dépôt par étudiant. Nom du dépôt : `{homework_prefix}{username_etudiant}`

---

### Scénario 2 : Projets d'équipe avec plusieurs étudiants

Exemple — `config_456_tpfinall.json` :

```json
{
    "organization": "420-andrelaurendeau",
    "template": "https://github.com/420-andrelaurendeau/420-456-AL-H25-tp-final",
    "branch": "main",
    "homework_prefix": "420-456-AL-A26-tp-final-",
    "teachers": [
        "didiertclaurendeau"
    ],
    "projets": [
        {
            "name": "lologram",
            "students": [
                "etudiant1",
                "etudiant2",
            ]
        },
        {
            "name": "instagram-clone",
            "students": [
                "user1",
                "user2",
                "user3"
            ]
        }
    ]
}
```

**Comportement :** Un dépôt par projet. Nom du dépôt : `{homework_prefix}{project_name}`

Tous les étudiants du projet reçoivent l'accès **push** (lecture + écriture).

---

### Configuration commune

| Champ | Description |
|-------|-------------|
| `organization` | Organisation GitHub dans laquelle les dépôts sont créés |
| `template` | URL du dépôt template à utiliser comme base |
| `branch` | Branche de référence du template |
| `homework_prefix` | Préfixe des noms de dépôts |
| `teachers` | Liste des enseignants (le **premier** est le propriétaire des dépôts) |
| `students` | *(Scénario 1)* Liste des identifiants GitHub des étudiants |
| `projets` | *(Scénario 2)* Liste des projets avec leurs équipes |

Le script détecte automatiquement le scénario selon la présence de `students` ou `projets` dans le fichier de configuration.

---

## Utilisation

```
./classroom.sh <commande> <fichier_config> [options]
```

### `create` — Créer les dépôts étudiants ou projets

```bash
./classroom.sh create config_417.json        # Travaux individuels
./classroom.sh create config_456_tpfinall.json  # Projets d'équipe
```

**Comportement selon le scénario :**

**Scénario 1 — Travaux individuels :**
- Crée un dépôt privé **par étudiant** dans l'organisation, à partir du template
- Nom du dépôt : `{homework_prefix}{username_etudiant}`
- L'étudiant reçoit l'accès **push** (lecture + écriture, sans droits admin)

**Scénario 2 — Projets d'équipe :**
- Crée un dépôt privé **par projet** dans l'organisation, à partir du template
- Nom du dépôt : `{homework_prefix}{project_name}`
- Chaque membre de l'équipe reçoit l'accès **push** (lecture + écriture)

**Dans les deux cas :**
- Chaque enseignant reçoit l'accès **admin**
- **Idempotent** : si un dépôt existe déjà, il est ignoré (les permissions sont tout de même réappliquées)

> **Note :** Les dépôts créés depuis un template GitHub ne sont pas des forks — ils sont indépendants du template.

---

### `report` — Rapport sur les dépôts

```bash
./classroom.sh report config_417.json        # Travaux individuels
./classroom.sh report config_456_tpfinall.json  # Projets d'équipe
```

Affiche un tableau récapitulatif :

**Scénario 1 — Travaux individuels :**
| Colonne | Description |
|---------|-------------|
| Repository | Nom du dépôt |
| Commits | Nombre de commits effectués par l'étudiant (max 100) |
| Branches | Liste des branches présentes |
| URL | Lien direct vers le dépôt GitHub |

**Scénario 2 — Projets d'équipe :**
| Colonne | Description |
|---------|-------------|
| Repository | Nom du dépôt du projet |
| Commits | Nombre total de commits dans le projet (max 100) |
| Branches | Liste des branches présentes |
| URL | Lien direct vers le dépôt GitHub |

---

### `clone` — Cloner les dépôts localement

```bash
./classroom.sh clone config_417.json [répertoire]        # Travaux individuels
./classroom.sh clone config_456_tpfinall.json [répertoire]  # Projets d'équipe
```

Clone chaque dépôt (individuel ou de projet) dans le répertoire spécifié (par défaut : répertoire courant).

- Si un dépôt est déjà cloné, effectue un `git pull --ff-only` pour le mettre à jour.

```bash
# Exemple : cloner les travaux individuels
./classroom.sh clone config_417.json ./clones

# Exemple : cloner les projets d'équipe
./classroom.sh clone config_456_tpfinall.json ./projets
```

---

### `sync` — Synchroniser avec le template

```bash
./classroom.sh sync config_417.json        # Travaux individuels
./classroom.sh sync config_456_tpfinall.json  # Projets d'équipe
```

Propage les nouveaux commits du template vers chaque dépôt (individuel ou de projet).

- Ajoute le template comme remote `upstream`
- Effectue un `git merge` de la branche de référence
- Pousse le résultat sur chaque dépôt
- En cas de **conflit de merge**, le dépôt concerné est ignoré et les instructions de résolution manuelle sont affichées

---

## Exemples complets

### Scénario 1 : Travaux individuels

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

### Scénario 2 : Projets d'équipe

```bash
# 1. Créer les dépôts pour tous les projets
./classroom.sh create config_456_tpfinall.json

# 2. Vérifier l'avancement des projets
./classroom.sh report config_456_tpfinall.json

# 3. Cloner tous les projets dans un dossier dédié
./classroom.sh clone config_456_tpfinall.json ./projets

# 4. Distribuer une mise à jour du template
./classroom.sh sync config_456_tpfinall.json
```
