import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';

import '../../core/constants/app_tokens.dart';
import '../../data/services/address_suggestion_service.dart';

class AddressSuggestionField extends StatefulWidget {
  const AddressSuggestionField({
    super.key,
    required this.addressController,
    required this.cityController,
    required this.districtController,
    required this.onSelected,
    this.labelText = 'Adresse',
    this.hintText = 'Adresse suchen',
  });

  final TextEditingController addressController;
  final TextEditingController cityController;
  final TextEditingController districtController;
  final ValueChanged<AddressSuggestion> onSelected;
  final String labelText;
  final String hintText;

  @override
  State<AddressSuggestionField> createState() => _AddressSuggestionFieldState();
}

class _AddressSuggestionFieldState extends State<AddressSuggestionField> {
  final AddressSuggestionService _service = AddressSuggestionService();
  Timer? _debounce;
  List<AddressSuggestion> _suggestions = const <AddressSuggestion>[];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: widget.addressController,
          textInputAction: TextInputAction.next,
          onChanged: _handleChanged,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : widget.addressController.text.trim().isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      widget.addressController.clear();
                      _handleChanged('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        if (_suggestions.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              children: _suggestions
                  .map(
                    (suggestion) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(
                        suggestion.addressLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        suggestion.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _selectSuggestion(suggestion),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ],
    );
  }

  void _handleChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _loading = false;
        _suggestions = const <AddressSuggestion>[];
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 280), () async {
      if (!mounted) {
        return;
      }
      setState(() => _loading = true);
      _lastQuery = query;
      try {
        final results = await _service.search(query);
        if (!mounted || _lastQuery != query) {
          return;
        }
        setState(() {
          _suggestions = results;
          _loading = false;
        });
      } catch (_) {
        if (!mounted || _lastQuery != query) {
          return;
        }
        setState(() {
          _suggestions = const <AddressSuggestion>[];
          _loading = false;
        });
      }
    });
  }

  void _selectSuggestion(AddressSuggestion suggestion) {
    widget.addressController.text = suggestion.addressLine;
    if (suggestion.city.isNotEmpty) {
      widget.cityController.text = suggestion.city;
    }
    if (suggestion.district.isNotEmpty) {
      widget.districtController.text = suggestion.district;
    }
    widget.onSelected(suggestion);
    setState(() {
      _suggestions = const <AddressSuggestion>[];
    });
    FocusScope.of(context).unfocus();
  }
}
