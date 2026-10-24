import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../theme/app_theme.dart';

/// App-bar voice input affordance used by the operational screens.
class VoiceAssistantButton extends StatefulWidget {
  const VoiceAssistantButton({super.key});

  @override
  State<VoiceAssistantButton> createState() => _VoiceAssistantButtonState();
}

class _VoiceAssistantButtonState extends State<VoiceAssistantButton> {
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() => _listening = false);
        }
      },
    );

    if (!mounted) {
      return;
    }
    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Entrada por voz indisponível neste aparelho.')),
      );
      return;
    }

    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(localeId: 'pt_BR'),
      onResult: (result) {
        if (!result.finalResult ||
            !mounted ||
            result.recognizedWords.trim().isEmpty) {
          return;
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Você disse: ${result.recognizedWords}')),
          );
      },
    );
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _listening ? 'Parar entrada por voz' : 'Usar entrada por voz',
      onPressed: _toggleListening,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Icon(
          _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
          key: ValueKey(_listening),
          color: _listening ? AppTheme.accentOrange : null,
        ),
      ),
    );
  }
}
