import SwiftUI
import Charts

struct AppColors {
    static let background = Color(hex: "0A0A0B")
    static let surface = Color(hex: "1C1C1E")
    static let accent = Color.blue
    static let textPrimary = Color.white
    static let textSecondary = Color.gray
    static let gradientStart = Color.blue.opacity(0.6)
    static let gradientEnd = Color.purple.opacity(0.4)
}

struct ModernCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(AppColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 8)
    }
}

// MARK: - Reusable Analytics Components

struct EnrollmentMetricCard: View {
    let title: String
    let enrollment: Int
    var momDiff: Int? = nil
    var momPct: Double? = nil
    var ytdDiff: Int? = nil
    var ytdPct: Double? = nil
    var isSelected: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(isSelected ? .white : .blue.opacity(0.8))
                    .kerning(0.5)
                    .lineLimit(1)
                Text(UIFormatter.formatNumber(enrollment))
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let diff = momDiff, let pct = momPct {
                    growthMiniMetric(label: "MoM", diff: diff, pct: pct)
                }
                if let diff = ytdDiff, let pct = ytdPct {
                    growthMiniMetric(label: "YTD", diff: diff, pct: pct)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? Color.blue.opacity(0.15) : AppColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.blue : Color.white.opacity(0.05), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? Color.blue.opacity(0.3) : Color.clear, radius: 10, x: 0, y: 0)
    }
    
    func growthMiniMetric(label: String, diff: Int, pct: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.gray)
            HStack(spacing: 2) {
                Text("\(diff >= 0 ? "+" : "")\(UIFormatter.formatNumber(diff))")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                Text("|")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.2))
                Text(String(format: "%.1f%%", pct))
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(diff >= 0 ? .green : .red)
        }
    }
}

// MARK: - Reusable Charts

struct MarketTrendChart: View {
    let trendData: [TrendPoint]
    @Binding var rawSelectedDate: Date?
    let chartDomain: ClosedRange<Int>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CustomSectionHeader(title: "Enrollment Trend")
            
            ModernCard {
                VStack(alignment: .leading, spacing: 12) {
                    Chart {
                        ForEach(trendData) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Enrollment", point.enrollment))
                                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 3))
                            
                            PointMark(x: .value("Date", point.date), y: .value("Enrollment", point.enrollment))
                                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                .symbolSize(30)
                            
                            if let snapped = snappedDate, Calendar.current.isDate(point.date, inSameDayAs: snapped) {
                                RuleMark(x: .value("Date", snapped))
                                    .foregroundStyle(Color.white.opacity(0.5))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                                PointMark(x: .value("Date", snapped), y: .value("Enrollment", point.enrollment))
                                    .foregroundStyle(.white)
                                    .symbolSize(80)
                            }
                        }
                    }
                    .chartYScale(domain: chartDomain)
                    .chartXSelection(value: $rawSelectedDate)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                            AxisValueLabel { if let intVal = value.as(Int.self) { Text(UIFormatter.compactFormat(intVal)) } }
                        }
                    }
                    .frame(height: 220)
                    .overlay(alignment: .topTrailing) {
                        if let snapped = snappedDate, let point = trendData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: snapped) }) {
                            ChartTooltip(date: snapped, label: "Market Volume", value: point.enrollment)
                                .offset(x: -10, y: 10)
                        }
                    }
                }
            }
        }
    }
    
    private var snappedDate: Date? {
        guard let raw = rawSelectedDate else { return nil }
        return trendData.min(by: { abs($0.date.timeIntervalSince(raw)) < abs($1.date.timeIntervalSince(raw)) })?.date
    }
}

struct CarrierComparisonChart: View {
    let carrierTrendData: [CarrierTrendPoint]
    let top5CarrierNames: [String]
    @Binding var rawCarrierSelectedDate: Date?
    
    private let chartColors: [Color] = [
        Color(hex: "3B82F6"), // Electric Blue
        Color(hex: "06B6D4"), // Vivid Cyan
        Color(hex: "F59E0B"), // Amber / Gold
        Color(hex: "EC4899"), // Magenta / Pink
        Color(hex: "10B981")  // Emerald Green
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CustomSectionHeader(title: "Carrier Comparison")
            
            ModernCard {
                VStack(alignment: .leading, spacing: 12) {
                    Chart {
                        ForEach(carrierTrendData) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Enrollment", point.enrollment)
                            )
                            .foregroundStyle(by: .value("Carrier", point.carrier))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Enrollment", point.enrollment)
                            )
                            .foregroundStyle(by: .value("Carrier", point.carrier))
                            .symbolSize(20)
                            
                            if let snapped = snappedCarrierDate, Calendar.current.isDate(point.date, inSameDayAs: snapped) {
                                RuleMark(x: .value("Date", snapped))
                                    .foregroundStyle(Color.white.opacity(0.3))
                                PointMark(x: .value("Date", snapped), y: .value("Enrollment", point.enrollment))
                                    .foregroundStyle(by: .value("Carrier", point.carrier))
                                    .symbolSize(60)
                            }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXSelection(value: $rawCarrierSelectedDate)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                            AxisValueLabel { if let intVal = value.as(Int.self) { Text(UIFormatter.compactFormat(intVal)) } }
                        }
                    }
                    .chartForegroundStyleScale(domain: top5CarrierNames, range: chartColors)
                    .chartLegend(position: .bottom, alignment: .center)
                    .frame(height: 220)
                    .overlay(alignment: .topTrailing) {
                        if let snapped = snappedCarrierDate {
                            let points = carrierTrendData.filter { Calendar.current.isDate($0.date, inSameDayAs: snapped) }
                            CarrierLeaderboardTooltip(date: snapped, points: points, colors: carrierColorMap)
                                .offset(x: -10, y: 10)
                        }
                    }
                }
            }
        }
    }
    
    private var snappedCarrierDate: Date? {
        guard let raw = rawCarrierSelectedDate else { return nil }
        return carrierTrendData.min(by: { abs($0.date.timeIntervalSince(raw)) < abs($1.date.timeIntervalSince(raw)) })?.date
    }
    
    private var carrierColorMap: [String: Color] {
        var map: [String: Color] = [:]
        for (index, name) in top5CarrierNames.enumerated() {
            map[name] = chartColors[index % chartColors.count]
        }
        return map
    }
}

struct ChartTooltip: View {
    let date: Date
    let label: String
    let value: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date, format: .dateTime.month().year()).font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
            Text(label).font(.system(size: 10)).foregroundColor(.white.opacity(0.7))
            Text(UIFormatter.formatNumber(value)).font(.system(size: 14, weight: .black, design: .rounded)).foregroundColor(.white)
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "1C1C1E")).shadow(color: .black.opacity(0.5), radius: 10))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

struct CarrierLeaderboardTooltip: View {
    let date: Date
    let points: [CarrierTrendPoint]
    let colors: [String: Color]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(date, format: .dateTime.month().year()).font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(points.sorted(by: { $0.enrollment > $1.enrollment })) { p in
                    HStack(spacing: 6) {
                        Circle().fill(colors[p.carrier] ?? .gray).frame(width: 6, height: 6)
                        Text(p.carrier.prefix(12)).font(.system(size: 9)).foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text(UIFormatter.compactFormat(p.enrollment)).font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                    }
                }
            }
        }
        .padding(10).frame(width: 160).background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "1C1C1E")).shadow(color: .black.opacity(0.5), radius: 10))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

struct CustomSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .black))
                .foregroundColor(.white.opacity(0.4))
                .kerning(1.2)
            if let sub = subtitle {
                Spacer()
                Text(sub)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.blue.opacity(0.6))
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Unified Header Component

struct PageHeader: View {
    let title: String
    let subtitle: String?
    @Binding var isMenuOpen: Bool
    var rightButton: AnyView? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 10) // Extra padding for status bar
            HStack(alignment: .center) {
                Button(action: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isMenuOpen = true } }) {
                    ZStack {
                        Circle().fill(AppColors.surface).frame(width: 40, height: 40)
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 2) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if let sub = subtitle {
                        Text(sub.uppercased())
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                if let rb = rightButton {
                    rb
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(AppColors.background.opacity(0.95))
            .background(VisualEffectView(effect: UIBlurEffect(style: .dark)))
            
            Divider().background(Color.white.opacity(0.1))
        }
    }
}

// MARK: - Filter Overlay Component

struct FilterOverlay: View {
    @Binding var filter: DashboardFilter
    let availableStates: [String]
    let availablePlanTypes: [String]
    @Binding var isPresented: Bool
    let onApply: () -> Void
    
    @State private var draft: DashboardFilter
    
    init(filter: Binding<DashboardFilter>, availableStates: [String], availablePlanTypes: [String], isPresented: Binding<Bool>, onApply: @escaping () -> Void) {
        self._filter = filter
        self._draft = State(initialValue: filter.wrappedValue)
        self.availableStates = availableStates
        self.availablePlanTypes = availablePlanTypes
        self._isPresented = isPresented
        self.onApply = onApply
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isPresented = false } }
            
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.2)).frame(width: 40, height: 6).padding(.top, 10).padding(.bottom, 10)
                
                HStack {
                    Button("Cancel") { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isPresented = false } }
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Text("Market Filters").font(.headline).foregroundColor(.white)
                    Spacer()
                    Button("Reset") { withAnimation(.spring()) { draft = DashboardFilter() } }
                        .foregroundColor(.red)
                }
                .padding(.horizontal).padding(.bottom, 16)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        filterSection(title: "Geography") {
                            Menu {
                                Button("All States") { draft.state = nil }
                                ForEach(availableStates, id: \.self) { s in Button(s) { draft.state = s } }
                            } label: {
                                HStack { Text(draft.state ?? "All States"); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption) }
                                .padding().background(Color.white.opacity(0.05)).cornerRadius(10)
                            }
                        }
                        
                        filterSection(title: "Plan Attributes") {
                            VStack(spacing: 20) {
                                Menu {
                                    Button("All Types") { draft.planType = nil }
                                    ForEach(availablePlanTypes, id: \.self) { t in Button(t) { draft.planType = t } }
                                } label: {
                                    HStack { Text(draft.planType ?? "All Plan Types"); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption) }
                                    .padding().background(Color.white.opacity(0.05)).cornerRadius(10)
                                }
                                
                                filterToggle(title: "EGWP", selection: $draft.egwp)
                                filterToggle(title: "SNP", selection: $draft.snp)
                                
                                if draft.snp == "Yes" {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("SNP SUB-TYPES").font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
                                        HStack(spacing: 12) {
                                            Toggle("D-SNP", isOn: $draft.dsnp).toggleStyle(FilterChipStyle())
                                            Toggle("C-SNP", isOn: $draft.csnp).toggleStyle(FilterChipStyle())
                                            Toggle("I-SNP", isOn: $draft.isnp).toggleStyle(FilterChipStyle())
                                        }
                                    }
                                    .padding(.top, 8).transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                        
                        Button(action: {
                            filter = draft; onApply()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isPresented = false }
                        }) {
                            Text("Apply Filters").font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(Color.blue).cornerRadius(12)
                        }
                        .padding(.top, 10)
                    }
                    .padding()
                    .padding(.bottom, 40)
                }
                .background(AppColors.background)
            }
            .background(AppColors.background)
            .cornerRadius(24, corners: [.topLeft, .topRight])
            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: -10)
        }
        .ignoresSafeArea()
    }
    
    func filterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.system(size: 11, weight: .black)).foregroundColor(.white.opacity(0.4)).kerning(1.2)
            content()
        }
    }
    
    func filterToggle(title: String, selection: Binding<String>) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            Spacer()
            Picker(title, selection: selection) {
                Text("All").tag("All")
                Text("Yes").tag("Yes")
                Text("No").tag("No")
            }
            .pickerStyle(.segmented).frame(width: 160)
        }
    }
}

struct FilterChipStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { configuration.isOn.toggle() } }) {
            configuration.label
                .font(.system(size: 12, weight: .bold))
                .padding(.vertical, 8).padding(.horizontal, 14)
                .background(configuration.isOn ? Color.blue : Color.white.opacity(0.05))
                .foregroundColor(.white).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: configuration.isOn ? 0 : 1))
        }
    }
}

// MARK: - Formatters

struct UIFormatter {
    static func formatNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
    
    static func compactFormat(_ n: Int) -> String {
        let num = Double(n)
        let isNegative = num < 0
        let absNum = abs(num)
        var result = ""
        if absNum >= 1_000_000 { result = String(format: "%.1fM", absNum / 1_000_000) }
        else if absNum >= 1_000 { result = String(format: "%.1fK", absNum / 1_000) }
        else { result = "\(Int(absNum))" }
        return (isNegative ? "-" : "") + result
    }
    
    static func growthString(current: Int, prior: Int?) -> String {
        guard let prior = prior, prior > 0 else { return "--" }
        let diff = current - prior
        let pct = (Double(diff) / Double(prior)) * 100.0
        return String(format: "%@%.1f%%", diff >= 0 ? "+" : "", pct)
    }
    
    static func growthColor(current: Int, prior: Int?) -> Color {
        guard let prior = prior, prior > 0 else { return .gray }
        return current >= prior ? .green : .red
    }
}

// MARK: - Utilities

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    func makeUIView(context: Context) -> UIVisualEffectView { UIVisualEffectView() }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) { uiView.effect = effect }
}

struct Theme {
    static func setup() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 17, weight: .bold)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 34, weight: .bold)]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
