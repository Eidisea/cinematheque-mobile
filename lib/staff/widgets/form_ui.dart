import 'package:flutter/material.dart';

import '../theme/staff_theme.dart';

// Form pieces of the website's admin (New / Edit screening, film), shared by the staff forms.

/// A white panel with a titled header line, as the website's form sections.
class FormPanel extends StatelessWidget {
  const FormPanel({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: StaffColors.surface,
        border: Border.all(color: StaffColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: StaffColors.border))),
            child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          ...children,
        ],
      ),
    );
  }
}

class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child, this.required = false, this.error, this.hint});

  final String label;
  final Widget child;
  final bool required;
  final String? error;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: StaffColors.gray700),
            children: [
              TextSpan(text: label),
              if (required) const TextSpan(text: ' *', style: TextStyle(color: StaffColors.danger)),
            ],
          )),
          const SizedBox(height: 6),
          child,
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: const TextStyle(fontSize: 12, color: StaffColors.textMuted)),
          ],
          if (error != null) ...[
            const SizedBox(height: 4),
            Text(error!, style: const TextStyle(fontSize: 12, color: StaffColors.danger)),
          ],
        ],
      ),
    );
  }
}

/// Two side-by-side choices (Film / Special programme, Free / Paid), as on the website.
class ChoiceToggle<T> extends StatelessWidget {
  const ChoiceToggle({super.key, required this.values, required this.current, required this.label, required this.onSelect, this.enabled = true});

  final List<T> values;
  final T current;
  final String Function(T) label;
  final ValueChanged<T> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          Semantics(
            button: true,
            selected: v == current,
            child: InkWell(
              onTap: enabled ? () => onSelect(v) : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: v == current ? StaffColors.brandTint : StaffColors.surface,
                  border: Border.all(color: v == current ? StaffColors.brand : StaffColors.borderStrong, width: v == current ? 1.5 : 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(v == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 16, color: v == current ? StaffColors.brand : StaffColors.gray400),
                    const SizedBox(width: 8),
                    Text(label(v),
                        style: TextStyle(fontSize: 14, color: enabled ? StaffColors.text : StaffColors.textMuted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class SelectBox<T> extends StatelessWidget {
  const SelectBox({super.key, required this.value, required this.hint, required this.items, required this.onChanged});

  final T? value;
  final String hint;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: StaffColors.surface,
        border: Border.all(color: StaffColors.borderStrong),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.containsKey(value) ? value : null,
          isExpanded: true,
          hint: Text(hint, style: const TextStyle(fontSize: 14, color: StaffColors.textMuted)),
          style: const TextStyle(fontSize: 14, color: StaffColors.text),
          items: [for (final e in items.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class PickerButton extends StatelessWidget {
  const PickerButton({super.key, required this.text, required this.icon, required this.onTap});

  final String text;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: onTap == null ? StaffColors.gray100 : StaffColors.surface,
          border: Border.all(color: StaffColors.borderStrong),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: StaffColors.gray400),
            const SizedBox(width: 8),
            Expanded(child: Text(text, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))),
          ],
        ),
      ),
    );
  }
}

class SummaryLine extends StatelessWidget {
  const SummaryLine(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 84, child: Text(label, style: const TextStyle(fontSize: 13, color: StaffColors.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
