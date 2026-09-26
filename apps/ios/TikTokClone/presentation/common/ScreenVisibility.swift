import SwiftUI

extension EnvironmentValues {
    // Onglet de la pile de navigation sélectionné, sans écran présenté par-dessus (vidéo seule) : les écrans
    // qui marquent lu (activité, conversation) ou lisent une vidéo n'agissent que s'ils sont réellement affichés.
    @Entry var isTabActive = true
}
