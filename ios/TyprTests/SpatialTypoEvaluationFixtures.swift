@testable import Typr

/// Fixed public/common words, not collected typing. Frozen for A/B comparisons.
/// ASCII-only here because the current visible keyboard has no umlaut key centres.
nonisolated enum SpatialTypoEvaluationFixtures {
    static let english = """
    about after again always another answer around before better between black bring brother business
    called change children city close coming could country course different dinner doing door down
    early earth enough every everything family father feel find first food found friend friends
    from getting girl give going good great green ground group guess hand happy hard
    have head hear heard heart help here high home hope hospital house hundred idea
    important inside into just keep kind kitchen know last late later leave left letter
    life light like little live long look looking love made make many matter maybe
    mean might mind minute money morning mother move much music must name near need
    never next nice night nothing number office often once only open other outside over
    paper parents
    """.split(whereSeparator: \.isWhitespace).map(String.init)

    static let german = """
    aber abend alle allein alles also alten andere anders anfang angst antwort arbeit auch
    aufgabe augen auto bald bauen beide beim beispiel bekommen besser besten bestimmt bett bild
    bitte bleiben blick blut brauchen bringen bruder buch dabei dadurch damals damit danach danke
    dann daran darauf darin darum dass davon dazu deine denken denn deshalb diese dieser
    doch doktor dort draussen drei durch eben egal eher eigen einfach eltern ende endlich
    etwas fahren fall familie fast fehler fenster fertig fest feuer finden finger fliegen folgen
    frage fragen frau frauen frei freuen freund freunde ganz geben gegen gehen gehst geld
    genau genug gerade gern gerne geschichte gesicht gestern gesund getan gibt gleich glauben gott
    gute guten haben halb hallo halten hand haus heben heimat heiss helfen herr herrn
    heute hier
    """.split(whereSeparator: \.isWhitespace).map(String.init)

    // Capitalised public nouns are deliberately lowercased before producing taps.
    static let germanNouns = ["Haus", "Mutter", "Vater", "Schule", "Wasser", "Freund", "Arbeit", "Fenster",
                              "Kind", "Nacht", "Morgen", "Woche", "Stadt", "Tisch", "Buch", "Sonne"]
    static let short = ["the", "and", "for", "not", "you", "can", "but", "all", "was", "now",
                        "der", "die", "das", "und", "ist", "mit", "aus", "nur", "gut", "tag"]
    // Neutral invented names/identifiers and public technical terms. Membership is checked
    // in the test: corpus entries are NOT silently counted as out-of-lexicon controls.
    static let novel = ["Velqora", "Nuvylo", "Zelmavi", "Torvexa", "Belnuzo", "Quvello", "Zanvori", "Pelquna",
                        "Mivzora", "Kelvuzo", "Rovqena", "Talvixo", "Nexqori", "Vunqela", "Zorvumi", "Dalqeno",
                        "Linquvo", "Falzumi", "Juvqora", "Xelvani", "Wunqero", "Cavzuli", "Qorvexa", "Zyvqeno",
                        "Vexqari", "Molvuzo", "Pinqeva", "Ruzqilo", "Telvuxa", "Yunqavi", "Zulqero", "Benqavi",
                        "Kubernetes", "OpenTelemetry", "ProtoBuf", "WASM", "QEMU", "GraphQL", "NVMe", "gRPC"]
    // Negative controls, all ASCII a-z (typable on the visible layout). Each was verified
    // offline as absent from BOTH keyboard-de.words and keyboard-en.words; the test re-checks
    // absence and does not count accidental corpus entries as outside controls.
    static let absent: [String] = [
        // Invented or common public person/place names.
        "Brennholm", "Kesterwald", "Ondravik", "Maltesund", "Vireloh", "Jastrowin", "Eldmarsk", "Trevanholt",
        "Quinsbrook", "Halvardin", "Orsenfeld", "Lidmarra", "Corvenhal", "Ysterbeck", "Margolin", "Dravenna",
        "Thessaly", "Wendmoor", "Faelwick", "Gostrava", "Ulvenrath", "Brisolde", "Okonkwo", "Nakashima",
        "Ravindran", "Szymanski", "Vasquezo", "Thorvaldsen", "Lindqvist", "Oyelaran", "Przybylski", "Wojcik",
        "Nguyenova", "Altenbruch", "Kleinwiesbach", "Oberstrelitz", "Hohenwartha", "Niederfelsing",
        "Brakelmund", "Ostervelde",
        // Public technical terms, tools and frameworks.
        "kubectl", "kustomize", "terraform", "ansible", "nginx", "postgres", "redis", "webpack", "pytest",
        "numpy", "laravel", "symfony", "svelte", "nextjs", "tailwind", "golang", "rustc", "pnpm", "homebrew",
        "systemd", "journalctl", "hyprland", "wayland", "xcodegen", "swiftui", "uikit", "grafana", "rabbitmq",
        "elasticsearch", "kibana", "gitlab", "github", "bitbucket", "dockerfile", "kubelet", "etcd", "istio",
        "argocd", "openssl", "sqlite", "mongodb", "mysql", "jsonl", "yaml", "toml", "llvm", "rustup", "venv",
        "pipx", "uvicorn", "fastapi", "pydantic", "typescript", "javascript", "nodejs", "deno", "esbuild",
        "eslint", "vitest", "xcode", "testflight", "actionlint", "shellcheck", "neovim", "tmux", "ripgrep",
        "vscode", "firebase", "supabase", "vercel", "netlify", "heroku", "cloudflare", "huggingface", "pytorch",
        "tensorflow", "jupyter", "matplotlib", "scipy", "sklearn", "kotlin", "swiftlint", "cocoapods", "gradle",
        "webhook", "localhost", "devops",
        // Invented or public product-like names, some with deliberate vowel drops (Flickr).
        "Zentrix", "Klyvo", "Brivana", "Quanteo", "Lumora", "Novexa", "Spotlio", "Fresqo", "Velocta", "Moxidan",
        "Trivago", "Zalando", "Lieferando", "Flickr", "Tumblr", "Lyft", "Fiverr", "Etsy", "Shopify", "Figma",
        "Trello", "Asana", "Canva", "Strava", "Komoot", "Duolingo", "Spotify", "Dropbox", "Airbnb", "Deliveroo",
        "Doordash", "Klarna", "Revolut", "Wolt", "Flixbus", "Rewe", "Edeka", "Rossmann",
        // Abbreviations and chat shorthand.
        "bzw", "usw", "evtl", "ggf", "inkl", "zzgl", "vllt", "imho", "afaik", "tbh", "idk", "omw", "brb",
        "lgtm", "wip", "mfg", "nvm", "smh", "irl", "pls", "kthx", "approx", "mgmt", "qty", "vgl", "bspw", "ugs",
        "lmk", "rofl",
        // German closed compounds of two lexicon nouns, absent as a whole.
        "hausfenster", "tischbuch", "fensterlampe", "kinderstuhl", "autobrief", "buchgarten", "zimmerlampe",
        "stadtwald", "nachtlampe", "morgenkaffee", "vaterbrief", "mutterstuhl", "freundbrief", "handlampe",
        "briefgeld", "zeitbahn", "tagwald", "bahnfeld", "wegstein", "waldweg", "feldblume", "baumstuhl",
        "steintisch", "brotglas", "milchglas", "kaffeeglas", "teeglas", "glastisch", "lichtfenster",
        "stuhlbein", "bettlampe", "hundebett", "katzenstuhl", "fischglas", "hausbuch", "tischlampe",
        "fensterbank", "wassertisch", "schulbuch", "autotisch", "buchtisch", "zimmertisch", "stadtgarten",
        "nachtzug", "morgenlicht", "sonnenhaus", "gartenstuhl", "gartenlampe", "waldhaus", "bergbahn",
        "feldweg", "steinhaus", "brottisch", "teetisch", "glasvogel", "lichttisch", "bettbuch", "katzenhaus",
        "vogelglas", "fischhaus", "geldtisch", "zeittisch", "tagzimmer", "kopfbuch", "hauskatze", "tischvogel",
        "fensterhund", "wasserhund", "schulhund", "autostein", "waldbrot", "feldtisch", "steinbrot",
        "kinderlampe", "zimmerbaum", "nachtvogel", "sonnenstuhl", "bergwald", "milchtisch",
        // English closed compounds absent as a whole.
        "doorframe", "keyring", "hairclip", "toolshed", "rainjacket", "sunhat", "dogbowl", "cupholder",
        "bikelock", "shoerack", "mailslot", "carkeys", "desklamp", "phonecase", "wallclock", "teaspoonful",
        "bookstand", "windowbox", "gardenhose", "coffeemug", "drawerknob", "raincover", "catflap", "birdbath",
        "handrail",
        // Intentional unusual spellings.
        "kewl", "gud", "tonite", "yesss", "rly", "srsly", "pleeease", "hiii", "okk", "yeeah", "Jaxon", "Mykel",
        "Jaxsen", "Brookelyn"
    ]
    // Rare-but-valid controls: lower-frequency public words present in the bundled corpus
    // (DE count 60-200, EN count 150-450 at selection; re-checked in the test).
    static let rare: [String] = [
        // German.
        "lehrten", "problemchen", "unterstand", "diskutiere", "gesalzen", "bodens", "vertrat", "kojote",
        "masseur", "rekordzeit", "liedern", "gruseliger", "halbgott", "verputzt", "direktem", "stromquelle",
        "kampfbereit", "montiert", "verliebter", "vergab", "fungieren", "fruchtbaren", "stadthalle", "rasante",
        "gierige", "weinprobe", "erhitzt", "eingehend", "saxophon", "bezahlter", "permanente", "wettbewerbe",
        "sprecherin", "humanoide", "amtierender", "knallharte", "virtuellen", "abzahlen", "hergeflogen",
        "fischchen", "zwanghaft", "benannte", "quacksalber", "ankommst", "echsen", "demzufolge", "vasen",
        "gebeugt", "gesamtsumme", "maiskolben", "detonieren", "tanzstunden", "yachthafen", "gerichten",
        "liedchen", "pavian", "freispruch", "schneiderin", "kostenloses", "zwirn", "plantagen", "urkomisch",
        "ferse", "wechselkurs", "reiseroute", "torten", "merkmal", "luchs",
        // English.
        "payoffs", "distillery", "worshippers", "eloquence", "marketed", "resonates", "shoplifter", "footstep",
        "clothesline", "dodgeball", "competency", "bunks", "whittling", "twiddle", "flyover", "thwart",
        "depositing", "rummage", "criticised", "shelved", "cuttlefish", "eased", "blighted", "showgirl",
        "electrics", "cobblers", "template", "progeny", "astonish", "tilting", "transistor", "countryman",
        "papyrus", "scholastic", "aspired", "propellant", "sweltering", "underlings", "rewinding", "trickling",
        "tubing", "frosted", "poplar", "lineman", "blare", "overshot", "coriander", "drunker", "monastic",
        "combatant", "fusing", "dislodge", "daffodil", "congenial", "struts", "twisty", "quarts", "restricting",
        "decoding", "membranes", "quieten", "entrenched", "rewrites", "omnipresent", "pickers", "marinated",
        "thunderous", "oodles", "beckons", "cashews", "latched", "jostle", "glacial", "playpen", "blogging",
        "contesting", "emanating"
    ]
}
