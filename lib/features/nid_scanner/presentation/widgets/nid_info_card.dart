import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NIDInfoCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onCopy;

  const NIDInfoCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  @override
  State<NIDInfoCard> createState() => _NIDInfoCardState();
}

class _NIDInfoCardState extends State<NIDInfoCard> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant NIDInfoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.icon, color: Colors.green[700], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _controller,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                )
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: widget.onCopy,
            tooltip: 'Copy',
            color: Colors.grey[600],
          ),
        ],
      ),
    );
  }
}
