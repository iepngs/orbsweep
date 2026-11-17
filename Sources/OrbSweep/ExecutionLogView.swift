import SwiftUI
import AppKit

struct ExecutionLogView: View {
    let text: String
    let isRunning: Bool
    @Binding var isExpanded: Bool
    private let teal = Color(red: 0.12, green: 0.65, blue: 0.57)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Image(systemName: "doc.text").foregroundStyle(teal)
                        Text("执行记录").font(.system(size: 13, weight: .semibold))
                        Text(isRunning ? "正在执行…" : "本次清理输出")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("执行记录")
                .accessibilityValue(isExpanded ? "已展开" : "已收起")

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("复制本次完整执行记录")
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            if isExpanded {
                Divider().padding(.horizontal, 14)
                ScrollView([.vertical, .horizontal]) {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.8))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                }
                .frame(minHeight: 36, idealHeight: 90, maxHeight: 120)
                .accessibilityLabel("执行记录内容")
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06)))
    }
}
