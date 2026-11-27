// Things the quizmaster says. Mirrors custom_components/popquiz/phrases.py.

public enum Phrases {
    public static let welcome =
        "Welcome to Decades: Pop Music Quiz! I'll play a short clip of a song. "
        + "Name the song, the artist, or both for double points. "
        + "Say repeat to hear it again, skip to pass, or exit game now to quit. "

    /// For a game where answers are typed rather than spoken.
    public static let welcomeTyped =
        "Welcome to Decades: Pop Music Quiz! I'll play a short clip of a song. "
        + "Type the song, the artist, or both for double points. "
        + "Use the buttons to hear it again or to skip. "

    public static let askPlayers = "How many players? Anywhere from one to six."

    /// No end punctuation: the game adds "." or ", or choose Holiday!" in season.
    public static let askCategory = "Pick a category, like 70s, 80s, or 2020s"

    public static let celebrations = [
        "Take a bow, you absolute music legend!",
        "Somebody call the Grammys!",
        "That's a chart-topping performance!",
        "Drop the mic!",
        "You've gone platinum!",
        "The crowd goes wild!",
        "Encore! Encore!",
        "A true rock star, ladies and gentlemen!",
        "Straight to number one with a bullet!",
        "That performance deserves a standing ovation!",
        "Your name belongs in lights!",
        "Pure gold. Frame that record!",
        "Legendary. Absolutely legendary!",
        "Now that's music to my ears!",
        "The Hall of Fame is on line one!",
        "Cue the confetti!",
    ]
}
