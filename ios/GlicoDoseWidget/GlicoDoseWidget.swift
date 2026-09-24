import AppIntents
import SwiftUI
import UIKit
import WidgetKit

private let widgetGroupId = "group.app.glicodose"
/// AppColors.primary #2F7CC4
private let appPrimary = Color(red: 0.184, green: 0.486, blue: 0.769)
/// AppPalette.light.primarySoft #E8F1F9
private let appPrimarySoft = Color(red: 0.910, green: 0.945, blue: 0.976)
/// AppColors.success #2E7D32
private let appSuccess = Color(red: 0.180, green: 0.490, blue: 0.196)

struct GlicoDoseWidgetConfigIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "GlicoDose"
  static var description = IntentDescription("Glicose Libre e insulina rápida ativa (IOB)")

  @Parameter(title: "Fundo transparente", default: false)
  var transparentBackground: Bool
}

struct GlicoDoseEntry: TimelineEntry {
  let date: Date
  let libreConnected: Bool
  let hasGlucose: Bool
  let glucoseMgdl: Int
  let trendLabel: String
  let glucoseAge: String
  let iobU: Int
  let syncing: Bool
  let lastError: String
  let transparentBackground: Bool
}

struct Provider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> GlicoDoseEntry {
    GlicoDoseEntry(
      date: Date(),
      libreConnected: true,
      hasGlucose: true,
      glucoseMgdl: 120,
      trendLabel: "→",
      glucoseAge: "agora",
      iobU: 2,
      syncing: false,
      lastError: "",
      transparentBackground: false
    )
  }

  func snapshot(
    for configuration: GlicoDoseWidgetConfigIntent,
    in context: Context
  ) async -> GlicoDoseEntry {
    loadEntry(date: Date(), transparentBackground: configuration.transparentBackground)
  }

  func timeline(
    for configuration: GlicoDoseWidgetConfigIntent,
    in context: Context
  ) async -> Timeline<GlicoDoseEntry> {
    let entry = loadEntry(
      date: Date(),
      transparentBackground: configuration.transparentBackground
    )
    let next = Date().addingTimeInterval(60)
    return Timeline(entries: [entry], policy: .after(next))
  }

  private func loadEntry(date: Date, transparentBackground: Bool) -> GlicoDoseEntry {
    let prefs = UserDefaults(suiteName: widgetGroupId)
    let recordedIso = prefs?.string(forKey: "glucose_recorded_at")
    let age = refreshedAge(iso: recordedIso) ?? (prefs?.string(forKey: "glucose_age") ?? "")
    return GlicoDoseEntry(
      date: date,
      libreConnected: prefs?.bool(forKey: "libre_connected") ?? false,
      hasGlucose: prefs?.bool(forKey: "has_glucose") ?? false,
      glucoseMgdl: prefs?.integer(forKey: "glucose_mgdl") ?? 0,
      trendLabel: prefs?.string(forKey: "trend_label") ?? "",
      glucoseAge: age,
      iobU: prefs?.integer(forKey: "iob_u") ?? 0,
      syncing: prefs?.bool(forKey: "syncing") ?? false,
      lastError: prefs?.string(forKey: "last_error") ?? "",
      transparentBackground: transparentBackground
    )
  }

  private func refreshedAge(iso: String?) -> String? {
    guard let iso, !iso.isEmpty else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: iso)
    if date == nil {
      formatter.formatOptions = [.withInternetDateTime]
      date = formatter.date(from: iso)
    }
    guard let at = date else { return nil }
    let minutes = Int(Date().timeIntervalSince(at) / 60)
    if minutes < 1 { return "agora" }
    if minutes < 60 { return "há \(minutes) min" }
    let hours = minutes / 60
    if hours < 24 { return "há \(hours) h" }
    return "há \(hours / 24) d"
  }
}

struct GlicoDoseWidgetEntryView: View {
  var entry: Provider.Entry

  private var chromeColor: Color {
    entry.transparentBackground ? .accentColor : appPrimary
  }

  private var glucoseColor: Color {
    if !entry.hasGlucose || entry.glucoseMgdl <= 0 { return .primary }
    if entry.glucoseMgdl < 70 { return Color(red: 0.89, green: 0.11, blue: 0.14) } // accent
    if entry.glucoseMgdl > 180 { return Color(red: 0.90, green: 0.32, blue: 0.0) } // warning
    return appSuccess
  }

  private var metaText: String {
    if entry.libreConnected && entry.hasGlucose && entry.glucoseMgdl > 0 {
      if entry.glucoseAge.isEmpty { return "mg/dL" }
      return "mg/dL · \(entry.glucoseAge)"
    }
    if entry.libreConnected { return "Libre conectado" }
    return "Libre off"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("GlicoDose")
          .font(.caption.weight(.bold))
          .foregroundColor(chromeColor)
        Spacer()
        if #available(iOSApplicationExtension 17.0, *) {
          Button(
            intent: BackgroundIntent(
              url: URL(string: "glicodose://syncLibre"),
              appGroup: widgetGroupId
            )
          ) {
            Image(systemName: "arrow.clockwise")
              .font(.caption.weight(.semibold))
          }
          .buttonStyle(.plain)
          .tint(chromeColor)
        }
      }

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(entry.hasGlucose && entry.glucoseMgdl > 0 ? "\(entry.glucoseMgdl)" : "—")
          .font(.system(size: 34, weight: .bold))
          .foregroundColor(glucoseColor)
          .minimumScaleFactor(0.6)
          .lineLimit(1)
        if !entry.trendLabel.isEmpty {
          Text(entry.trendLabel)
            .font(.title2.weight(.bold))
            .foregroundColor(glucoseColor)
        }
      }

      Text(metaText)
        .font(.caption2)
        .foregroundColor(.secondary)
        .lineLimit(1)

      Text("\(entry.iobU) U ativas")
        .font(.subheadline.weight(.bold))
        .foregroundColor(.primary)
        .lineLimit(1)

      if entry.syncing {
        Text("Atualizando…")
          .font(.caption2)
          .foregroundColor(.secondary)
      } else if !entry.lastError.isEmpty {
        Text(entry.lastError)
          .font(.caption2)
          .foregroundColor(.red)
          .lineLimit(1)
      }
    }
    .padding(4)
  }
}

@main
struct GlicoDoseWidget: Widget {
  let kind: String = "GlicoDoseWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: kind,
      intent: GlicoDoseWidgetConfigIntent.self,
      provider: Provider()
    ) { entry in
      if #available(iOSApplicationExtension 17.0, *) {
        GlicoDoseWidgetEntryView(entry: entry)
          .modifier(GlicoDoseWidgetBackground(transparent: entry.transparentBackground))
      } else {
        GlicoDoseWidgetEntryView(entry: entry)
          .padding()
          .background(entry.transparentBackground ? Color.clear : appPrimarySoft)
      }
    }
    .configurationDisplayName("GlicoDose")
    .description("Glicose Libre e insulina rápida ativa (IOB)")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@available(iOSApplicationExtension 17.0, *)
private struct GlicoDoseWidgetBackground: ViewModifier {
  let transparent: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if transparent {
      content.containerBackground(.clear, for: .widget)
    } else {
      content.containerBackground(appPrimarySoft, for: .widget)
    }
  }
}

#if DEBUG
struct GlicoDoseWidget_Previews: PreviewProvider {
  static var previews: some View {
    GlicoDoseWidgetEntryView(
      entry: GlicoDoseEntry(
        date: Date(),
        libreConnected: true,
        hasGlucose: true,
        glucoseMgdl: 142,
        trendLabel: "↑",
        glucoseAge: "há 3 min",
        iobU: 3,
        syncing: false,
        lastError: "",
        transparentBackground: false
      )
    )
    .previewContext(WidgetPreviewContext(family: .systemSmall))
  }
}
#endif
