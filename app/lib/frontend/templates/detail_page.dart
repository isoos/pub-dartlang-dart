// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:intl/intl.dart';

import '_cache.dart';

final wideHeaderDetailPageClassName = '-wide-header-detail-page';

/// Renders the `shared/detail/header.mustache` template
///
/// The like button in the header will not be displayed when [isLiked] is null.
String renderDetailHeader({
  String? title,
  String? titleHtml,
  String? imageUrl,
  int? packageLikes,
  bool? isLiked,
  bool isFlutterFavorite = false,
  String? metadataHtml,
  String? tagsHtml,

  /// Set true for more whitespace in the header.
  bool isLoose = false,
}) {
  if ((title == null && titleHtml == null) ||
      (title != null && titleHtml != null)) {
    throw ArgumentError(
        'Exactly one of `title` and `titleHtml` must be specified.');
  }
  return templateCache.renderTemplate('shared/detail/header', {
    'is_loose': isLoose,
    'title_html': titleHtml ?? htmlEscape.convert(title!),
    'metadata_html': metadataHtml,
    'tags_html': tagsHtml,
    'like_count': _formatPackageLikes(packageLikes),
    'is_liked': isLiked,
    'has_likes': isLiked != null,
    'image_url': imageUrl,
    'has_image_url': imageUrl != null && imageUrl.isNotEmpty,
    'has_banners': isFlutterFavorite,
    'is_flutter_favorite': isFlutterFavorite,
  });
}

// keep in-sync with pkg/web_app/lib/src/likes.dart
String? _formatPackageLikes(int? likesCount) {
  if (likesCount == null) return null;
  return NumberFormat.compact().format(likesCount);
}

/// Renders the `shared/detail/page.mustache` template
String renderDetailPage({
  required String headerHtml,
  required List<Tab> tabs,
  required String? infoBoxHtml,
  String? infoBoxLead,
  String? footerHtml,
}) {
  return templateCache.renderTemplate('shared/detail/page', {
    'header_html': headerHtml,
    'tabs_html': renderDetailTabs(tabs),
    'info_box_lead': infoBoxLead,
    'has_info_box': infoBoxHtml != null,
    'info_box_html': infoBoxHtml,
    'footer_html': footerHtml,
  });
}

/// Renders the `views/shared/detail/tabs.mustache` template.
String renderDetailTabs(List<Tab> tabs) {
  // active: the first one with content
  for (Tab tab in tabs) {
    if (tab.contentHtml != null) {
      tab.isActive = true;
      break;
    }
  }
  final values = {'tabs': tabs.map((t) => t._toMustacheData()).toList()};
  return templateCache.renderTemplate('shared/detail/tabs', values);
}

/// Defines the header and content part of a tab.
class Tab {
  final String id;
  final String titleHtml;
  final String? contentHtml;
  final bool isMarkdown;
  final bool hasHref;
  bool isActive = false;

  Tab.withContent({
    required this.id,
    String? title,
    String? titleHtml,
    required this.contentHtml,
    this.isMarkdown = false,
    this.hasHref = false,
  }) : titleHtml = titleHtml ?? htmlEscape.convert(title!);

  Tab.withLink({
    required this.id,
    String? title,
    String? titleHtml,
    required String href,
  })  : titleHtml =
            '<a href="$href">${titleHtml ?? htmlEscape.convert(title!)}</a>',
        contentHtml = null,
        isMarkdown = false,
        hasHref = true;

  Map _toMustacheData() {
    final titleClasses = <String>[
      'detail-tab',
      contentHtml == null ? 'tab-link' : 'tab-button',
      'detail-tab-$id-title',
      if (isActive) '-active',
    ];
    final contentClasses = <String>[
      'tab-content',
      'detail-tab-$id-content',
      if (isActive) '-active',
      if (isMarkdown) 'markdown-body',
    ];
    return <String, dynamic>{
      'title_classes': titleClasses.join(' '),
      'title_html': titleHtml,
      'content_classes': contentClasses.join(' '),
      'content_html': contentHtml,
      'has_content': contentHtml != null,
    };
  }
}
