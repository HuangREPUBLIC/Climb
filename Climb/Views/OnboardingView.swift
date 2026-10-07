import SwiftUI
import SwiftData

/// The first screens a new player sees: what Climb does, then signing in
/// with a Riot ID. ContentView shows this until an account is linked; after
/// that the account sheet (LinkAccountView) handles syncing and switching.
struct OnboardingView: View {
    /// Set from the first sync tap until a sync succeeds. The account row
    /// is saved early in an import, and without this ContentView would swap
    /// to the app mid-import — or behind a failure the player never saw.
    @Binding var isLinking: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var page = 0
    @State private var gameName = ""
    @State private var tagLine = ""
    @State private var platform: RiotPlatform = .jp1
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingKeys = false
    @FocusState private var focusedField: RiotIDInput.Field?

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 96
    @ScaledMetric(relativeTo: .body) private var pointIconSize: CGFloat = 36

    private struct Intro {
        let icon: String
        let title: String
        let message: String
        let points: [(icon: String, text: String)]
    }

    private let intros = [
        Intro(
            icon: "chart.line.uptrend.xyaxis",
            title: "Welcome to Climb",
            message: "Your League of Legends games, explained in plain language.",
            points: [
                ("list.bullet.rectangle.portrait.fill", "Every match with a 0–10 rating against the other nine players"),
                ("chart.bar.xaxis", "Trends across your last 20 games"),
                ("star.circle.fill", "Champion builds and tier lists")
            ]
        ),
        Intro(
            icon: "sparkles",
            title: "An AI coach for every game",
            message: "After each match Climb shows what decided it, in charts rather than walls of text.",
            points: [
                ("checkmark.seal.fill", "What went well, and what cost you the game"),
                ("target", "One thing to try next game"),
                ("lock.fill", "Your games stay on this device")
            ]
        )
    ]

    private var loginPage: Int { intros.count }

    private var canSync: Bool { RiotIDInput.isComplete(gameName: gameName, tagLine: tagLine) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < loginPage {
                    Button("Skip") { page = loginPage }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
            }
            .frame(minHeight: 44)

            TabView(selection: $page) {
                ForEach(intros.indices, id: \.self) { index in
                    introPage(intros[index]).tag(index)
                }
                loginForm.tag(loginPage)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .disabled(isWorking)

            pageDots
                .padding(.vertical, 12)

            primaryButton
                .padding(.bottom, 12)
        }
        .background(backdrop)
        .animation(.snappy, value: page)
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.error, trigger: errorMessage) { _, new in new != nil }
        .sheet(isPresented: $showingKeys) {
            NavigationStack { APIKeysView() }
        }
    }

    // MARK: - Pages

    private func introPage(_ intro: Intro) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                hero(intro.icon)
                    .padding(.top, 24)
                VStack(spacing: 8) {
                    Text(intro.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(intro.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(intro.points, id: \.text) { point in
                        HStack(spacing: 14) {
                            Image(systemName: point.icon)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: pointIconSize, height: pointIconSize)
                                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                                .accessibilityHidden(true)
                            Text(point.text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .cardSurface()
            }
            .padding(.horizontal, 24)
            .readableContentWidth(520)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var loginForm: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero("person.crop.circle.badge.checkmark")
                    .padding(.top, 24)
                VStack(spacing: 8) {
                    Text("Sign in with your Riot ID")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text("It's the name and tag at the top right of the League client, like Faker#KR1.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Riot ID")
                        .font(.headline)
                    RiotIDInput(gameName: $gameName, tagLine: $tagLine, platform: $platform, focus: $focusedField, submitLabel: .go) {
                        if canSync { sync() }
                    }
                }
                .cardSurface()

                if let errorMessage { ErrorCard(message: errorMessage) }

                VStack(spacing: 6) {
                    Text("Climb reads public match data through Riot's API. Nothing is posted to your account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        showingKeys = true
                    } label: {
                        Label("API Keys", systemImage: "key")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            .padding(.horizontal, 24)
            .readableContentWidth(520)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func hero(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: heroSize * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: heroSize, height: heroSize)
            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: heroSize * 0.28, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 8)
            .accessibilityHidden(true)
    }

    // MARK: - Chrome

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0...loginPage, id: \.self) { index in
                Capsule()
                    .fill(index == page ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.secondary.opacity(0.25)))
                    .frame(width: index == page ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(loginPage + 1)")
    }

    private var primaryButton: some View {
        let onLogin = page == loginPage
        return VStack(spacing: 8) {
            PrimaryButton(title: isWorking ? "Syncing…" : onLogin ? "Start syncing" : "Continue",
                          isWorking: isWorking, isEnabled: !onLogin || canSync) {
                if onLogin { sync() } else { page += 1 }
            }

            if isWorking {
                Text("Importing your last 20 games. The first sync takes a moment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .readableContentWidth(520)
    }

    private var backdrop: some View {
        ZStack(alignment: .top) {
            Theme.background
            Circle()
                .fill(Theme.accentGradient)
                .frame(width: 460, height: 460)
                .blur(radius: 120)
                .opacity(0.3)
                .offset(y: -260)
        }
        .ignoresSafeArea()
    }

    // MARK: - Sync

    private func sync() {
        focusedField = nil
        errorMessage = nil
        isWorking = true
        isLinking = true
        Task {
            do {
                try await MatchImportService.linkAndSync(
                    gameName: gameName.trimmingCharacters(in: .whitespaces),
                    tagLine: tagLine.trimmingCharacters(in: .whitespaces),
                    platform: platform,
                    gamesToSync: [.league],
                    context: modelContext
                )
                isWorking = false
                // ContentView swaps to the app.
                isLinking = false
            } catch {
                isWorking = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
