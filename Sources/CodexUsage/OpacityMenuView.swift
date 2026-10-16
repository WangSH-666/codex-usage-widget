import AppKit

/// A native menu control: changing the background keeps text and rings legible.
@MainActor final class OpacityMenuView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let slider: NSSlider
    private let onChange: (Double) -> Void

    init(value: Double, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        slider = NSSlider(value: value * 100, minValue: 0, maxValue: 100, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 248, height: 76))
        label.frame = NSRect(x: 18, y: 46, width: 212, height: 18)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        slider.frame = NSRect(x: 18, y: 14, width: 212, height: 24)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changeValue)
        slider.setAccessibilityLabel("背景不透明度，0到100百分比")
        addSubview(label)
        addSubview(slider)
        updateLabel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func changeValue() {
        slider.doubleValue = slider.doubleValue.rounded()
        updateLabel()
        onChange(slider.doubleValue / 100)
    }

    private func updateLabel() {
        label.stringValue = "背景不透明度  \(Int(slider.doubleValue.rounded()))%"
    }
}
