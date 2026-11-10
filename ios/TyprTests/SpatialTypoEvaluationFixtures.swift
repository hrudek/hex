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
}
