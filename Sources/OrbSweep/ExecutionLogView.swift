import SwiftUI
import AppKit

struct ExecutionLogView: View {
    let text: String
    let isRunning: Bool
    private let teal = Color(red: 0.12, green: 0.65, blue: 0.57)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text").foregroundStyle(teal)
                Text("执行记录").font(.system(size: 13, weight: .semibold))
                Text(text.isEmpty ? "等待清理" : isRunning ? "正在执行…" : "本次清理输出")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)

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
                .disabled(text.isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            Divider().padding(.horizontal, 14)
            // Keep output's intrinsic size out of the dashboard's layout.
            GeometryReader { geometry in
                content
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(height: 120)
            .clipped()
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06)))
    }

    @ViewBuilder
    private var content: some View {
        if text.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 20))
                    .foregroundStyle(teal.opacity(0.65))
                    .frame(width: 40, height: 40)
                    .background(teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text("暂无执行记录").font(.system(size: 12, weight: .medium))
                    Text("清理后的执行详情会显示在这里")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
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
            .accessibilityLabel("执行记录内容")
        }
    }
}
