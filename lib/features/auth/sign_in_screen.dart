import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import 'sign_in_view.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.close), onPressed: () => context.pop())
            : null,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: MaxWidth(
            maxWidth: 460,
            child: SignInView(
              onSignedIn: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
