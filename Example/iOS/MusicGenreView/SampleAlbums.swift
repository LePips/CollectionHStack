import Foundation
import SwiftUI

// Generated by ChatGPT

struct SampleAlbum: Hashable {
    let artist: String
    let album: String
    let color: Color
}

let sampleAlbums: [SampleAlbum] = [
    ("Luna Lyric", "Celestial Serenade", (176, 224, 230)), // Pastel Turquoise
    ("Echo Ember", "Whispers of Twilight", (255, 182, 193)), // Pastel Pink
    ("Aurora Harmony", "Ephemeral Elegance", (173, 216, 230)), // Pastel Blue
    ("Caden Crescendo", "Sonic Canvas", (152, 251, 152)), // Pastel Green
    ("Melody Moon", "Midnight Dreamscape", (240, 230, 140)), // Pastel Khaki
    ("Serene Sonata", "Harmonious Horizon", (255, 228, 196)), // Pastel Bisque
    ("Zephyr Zenith", "Whirlwind Melodies", (218, 112, 214)), // Pastel Orchid
    ("Sapphire Symphony", "Azure Resonance", (255, 218, 185)), // Pastel Peach
    ("Veronica Velvet", "Velvet Reverie", (144, 238, 144)), // Pastel Light Green
    ("Icarus Iris", "Iridescent Echoes", (255, 228, 196)), // Pastel Bisque
    ("Crimson Crescendo", "Scarlet Serenade", (176, 224, 230)), // Pastel Turquoise
    ("Lilac Lyric", "Lavender Lullaby", (255, 182, 193)), // Pastel Pink
    ("Astral Anthem", "Galactic Harmony", (173, 216, 230)), // Pastel Blue
    ("Breeze Ballad", "Whispering Winds", (152, 251, 152)), // Pastel Green
    ("Solstice Serenade", "Sunset Sonata", (240, 230, 140)), // Pastel Khaki
    ("Harmony Hues", "Melodic Palette", (255, 228, 196)), // Pastel Bisque
    ("Zara Zenith", "Zenith Zephyr", (218, 112, 214)), // Pastel Orchid
    ("Marina Melisma", "Aquamarine Aria", (255, 218, 185)), // Pastel Peach
    ("Violet Verse", "Velvet Violetta", (144, 238, 144)), // Pastel Light Green
    ("Ethereal Ensemble", "Enchanted Echoes", (255, 228, 196)), // Pastel Bisque
    ("Phoenix Pizzicato", "Rising Melodies", (176, 224, 230)), // Pastel Turquoise
    ("Aetherial Alto", "Whispers of the Aether", (255, 182, 193)), // Pastel Pink
    ("Celestial Crooner", "Stellar Serenades", (173, 216, 230)), // Pastel Blue
    ("Mystic Minuet", "Enigmatic Ensemble", (152, 251, 152)), // Pastel Green
    ("Zephyr Zither", "Aeolian Ambience", (240, 230, 140)), // Pastel Khaki
    ("Seraphic Soprano", "Heavenly Harmony", (255, 228, 196)), // Pastel Bisque
    ("Silken Songstress", "Velvet Vibration", (218, 112, 214)), // Pastel Orchid
    ("Aqua Aria", "Turquoise Tranquility", (255, 218, 185)), // Pastel Peach
    ("Eclipsed Euphony", "Shadows of Sound", (144, 238, 144)), // Pastel Light Green
    ("Lullaby Luminance", "Dreamy Dusk Serenade", (255, 228, 196)), // Pastel Bisque
    ("Velvet Virtuoso", "Velvet Visions", (176, 224, 230)), // Pastel Turquoise
    ("Iridescent Inamorata", "Luminous Love Songs", (255, 182, 193)), // Pastel Pink
    ("Azure Aria", "Sapphire Serenity", (173, 216, 230)), // Pastel Blue
    ("Meadow Melisma", "Harmony in the Hills", (152, 251, 152)), // Pastel Green
    ("Opal Overture", "Opalescent Opus", (240, 230, 140)), // Pastel Khaki
    ("Sonic Seraph", "Ethereal Echoes", (255, 228, 196)), // Pastel Bisque
    ("Lilting Lullaby", "Serenade of the Breeze", (218, 112, 214)), // Pastel Orchid
    ("Cerulean Croon", "Cerulean Crescendo", (255, 218, 185)), // Pastel Peach
    ("Twilight Tenor", "Melodies at Dusk", (144, 238, 144)), // Pastel Light Green
    ("Coral Cadence", "Coral Cove Concerto", (255, 228, 196)), // Pastel Bisque
].map { raw in
    SampleAlbum(
        artist: raw.0,
        album: raw.1,
        color: Color(red: raw.2.0 / 255, green: raw.2.1 / 255, blue: raw.2.2 / 255)
    )
}