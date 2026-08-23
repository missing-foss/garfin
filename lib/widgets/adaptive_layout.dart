// SPDX-FileCopyrightText: 2026 missing-foss
//
// SPDX-License-Identifier: GPL-3.0-or-later

/// The widths at which Garfin's layout changes, in one place (#95).
///
/// Every one of these is read off the **constraints a widget is handed**, never
/// off `MediaQuery`. That is the correction #108 arrived at for the grid: the
/// window and the space a widget actually gets are different numbers in
/// split-screen, on a folded foldable, and — now — beside a navigation rail or
/// an assign panel, and it is the second one that decides whether a layout
/// fits. `MediaQuery.sizeOf` remains the right input for questions about the
/// *window*; there are none left here.
library;

import 'package:flutter/material.dart';

/// Where a column of rows stops widening.
///
/// A chosen number, not a fitted one: at Nunito's body size 640dp is roughly 70
/// characters, near the top of the comfortable range for a line of prose, and
/// it keeps a `SwitchListTile`'s label and its switch inside one glance. The
/// alternative — letting Settings run the full 1280dp of a tablet in landscape
/// — parks every trailing control a hand's width from the label it belongs to.
///
/// Deliberately narrower than Material's 840dp pane guidance, because these are
/// single columns of text and controls rather than panes of content.
const double kReadableMaxWidth = 640;

/// Where the bottom navigation bar becomes a rail — Material 3's own figure.
///
/// A bottom bar on a wide screen puts the primary navigation as far from the
/// content as the geometry allows, and on a tablet in landscape that is a
/// genuine reach rather than a nicety.
const double kRailBreakpoint = 600;

/// Where the rail puts its labels beside the icons rather than under them.
const double kExtendedRailBreakpoint = 1240;

/// Where the library shows the grid and the write preview at the same time.
///
/// Material's "expanded" class. Below it the grid would be left with less than
/// [kAssignPanelWidth] of its own, which is the point at which keeping the grid
/// visible stops being worth anything.
const double kTwoPaneBreakpoint = 840;

/// How wide the assign panel is when it sits beside the grid.
const double kAssignPanelWidth = 360;

/// [base] widened until the content inside it is no wider than
/// [kReadableMaxWidth].
///
/// The cap is on the **content**, so a widget's own padding sits outside it and
/// every screen ends up with the same column width whatever padding it happens
/// to declare. Capping the padded box instead would make Settings and About
/// disagree by exactly the difference in their insets.
///
/// **For a scrolling widget, this belongs in its `padding`, not around it.**
/// Wrapping a `ListView` in a `ConstrainedBox` narrows the scrollable itself,
/// so on a tablet a drag started in the margin scrolls nothing and the
/// scrollbar moves inward to meet the text. Passing the insets to the list
/// leaves the scroll target and the scrollbar at the window's edge and moves
/// only what is drawn. Use [ReadableWidth] for content that does not scroll.
///
/// An unbounded width — inside a `Row`, or a shrink-wrapping list — is returned
/// unchanged rather than clamped against infinity.
EdgeInsets readableInsets(
  BoxConstraints constraints, [
  EdgeInsets base = EdgeInsets.zero,
]) {
  if (!constraints.hasBoundedWidth) return base;
  final slack = constraints.maxWidth - base.horizontal - kReadableMaxWidth;
  if (slack <= 0) return base;
  final gutter = slack / 2;
  return base.copyWith(left: base.left + gutter, right: base.right + gutter);
}

/// A [ListView] whose rows stop widening at [kReadableMaxWidth].
///
/// A widget rather than a convention so that "every list screen is capped" is
/// one grep — `ReadableList` — instead of five call sites that each had to
/// remember. It takes the constraints it is given, so a list inside a narrower
/// pane than the window caps against the pane.
class ReadableList extends StatelessWidget {
  const ReadableList({
    super.key,
    this.padding = EdgeInsets.zero,
    required this.children,
  })  : itemCount = null,
        itemBuilder = null,
        separatorBuilder = null;

  const ReadableList.separated({
    super.key,
    this.padding = EdgeInsets.zero,
    required this.itemCount,
    required this.itemBuilder,
    required this.separatorBuilder,
  }) : children = null;

  /// The list's own padding, before the cap widens it.
  final EdgeInsets padding;

  /// Set by the default constructor; null on [ReadableList.separated].
  final List<Widget>? children;

  /// Set by [ReadableList.separated]; null on the default constructor.
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final insets = readableInsets(constraints, padding);
          final rows = children;
          if (rows != null) return ListView(padding: insets, children: rows);
          return ListView.separated(
            padding: insets,
            itemCount: itemCount!,
            itemBuilder: itemBuilder!,
            separatorBuilder: separatorBuilder!,
          );
        },
      );
}

/// A [SingleChildScrollView] under the same cap, for the forms.
///
/// Sign-in, the lock screen and the one-time unlock question are a column of
/// fields and buttons; stretched across a tablet in landscape a text field
/// becomes a line nobody wants to read back.
class ReadableScroll extends StatelessWidget {
  const ReadableScroll({
    super.key,
    this.padding = EdgeInsets.zero,
    required this.child,
  });

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: readableInsets(constraints, padding),
          child: child,
        ),
      );
}

/// The same cap for content that does not scroll — a sheet, a panel.
///
/// A modal bottom sheet is the case this exists for: it spans the whole window
/// by default, so on a tablet the assign preview's switches end up a hand's
/// width from the names they belong to, exactly as the list screens did.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({
    super.key,
    required this.child,
    this.maxWidth = kReadableMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        // Shrink-wraps vertically. Without this a sheet wrapped in it takes
        // the full height it is offered instead of the height of its contents,
        // which on a tablet is a preview of two switches over most of a screen.
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}
