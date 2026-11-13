import SwiftUI

struct MenuPickerView: View {
    let catalog: MenuCatalog?
    let onSelect: (MenuDrink) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [MenuDrink] {
        guard let catalog else { return [] }
        return Array(catalog.searchDrinks(query: query).prefix(150))
    }

    var body: some View {
        Group {
            if catalog == nil {
                ContentUnavailableView(
                    "菜单暂不可用",
                    systemImage: "list.bullet.rectangle",
                    description: Text("仍可在记录表单中手动填写品牌和饮品名称。")
                )
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "搜索内置菜单",
                    systemImage: "magnifyingglass",
                    description: Text("输入品牌、饮品名称或别名。也可以直接手动记录自定义饮品。")
                )
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { drink in
                    Button {
                        onSelect(drink)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(drink.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(statusLabel(drink.status))
                                    .font(.caption)
                                    .foregroundStyle(drink.status == "verified" ? .green : .secondary)
                            }
                            Text(drink.brandName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !drink.source.isEmpty {
                                Text(drink.source)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .overlay(alignment: .top) {
                    if results.count == 150 {
                        Text("显示前 150 项，请继续缩小搜索范围")
                            .font(.caption)
                            .padding(8)
                            .background(.thinMaterial, in: Capsule())
                            .padding(.top, 6)
                    }
                }
            }
        }
        .navigationTitle("选择菜单饮品")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "品牌、饮品或别名")
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "verified": "已核验"
        case "pending": "待核验"
        case "unavailable": "已下架"
        default: status.isEmpty ? "状态未知" : status
        }
    }
}
