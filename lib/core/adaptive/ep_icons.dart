import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'platform.dart';

/// One icon vocabulary, two glyph sets: SF-style Cupertino icons on iOS,
/// Material Symbols on Android. Screens ask for the role, never the glyph.
enum EpIcon {
  today(CupertinoIcons.rectangle_stack, Icons.view_agenda_outlined),
  domains(CupertinoIcons.globe, Icons.language),
  mail(CupertinoIcons.envelope, Icons.mail_outline),
  compute(CupertinoIcons.bolt, Icons.bolt_outlined),
  settings(CupertinoIcons.gear, Icons.settings_outlined),
  sidebar(CupertinoIcons.sidebar_left, Icons.view_sidebar_outlined),
  add(CupertinoIcons.add, Icons.add),
  search(CupertinoIcons.search, Icons.search),
  more(CupertinoIcons.ellipsis_circle, Icons.more_vert),
  reply(CupertinoIcons.reply, Icons.reply),
  replyAll(CupertinoIcons.reply_all, Icons.reply_all),
  forward(CupertinoIcons.arrowshape_turn_up_right, Icons.forward),
  archive(CupertinoIcons.archivebox, Icons.archive_outlined),
  trash(CupertinoIcons.trash, Icons.delete_outline),
  star(CupertinoIcons.star, Icons.star_border),
  starFill(CupertinoIcons.star_fill, Icons.star),
  attach(CupertinoIcons.paperclip, Icons.attach_file),
  send(CupertinoIcons.paperplane, Icons.send),
  compose(CupertinoIcons.square_pencil, Icons.edit_outlined),
  refresh(CupertinoIcons.arrow_clockwise, Icons.refresh),
  lock(CupertinoIcons.lock, Icons.lock_outline),
  shield(CupertinoIcons.shield, Icons.shield_outlined),
  chart(CupertinoIcons.chart_bar, Icons.bar_chart),
  cloud(CupertinoIcons.cloud, Icons.cloud_outlined),
  pause(CupertinoIcons.pause_circle, Icons.pause_circle_outline),
  play(CupertinoIcons.play_circle, Icons.play_circle_outline),
  warning(CupertinoIcons.exclamationmark_triangle, Icons.warning_amber),
  check(CupertinoIcons.checkmark_alt, Icons.check),
  checkCircle(CupertinoIcons.checkmark_circle, Icons.check_circle_outline),
  close(CupertinoIcons.xmark, Icons.close),
  copy(CupertinoIcons.doc_on_doc, Icons.copy),
  share(CupertinoIcons.share, Icons.share),
  chevron(CupertinoIcons.chevron_right, Icons.chevron_right),
  link(CupertinoIcons.link, Icons.link),
  key(CupertinoIcons.lock_shield, Icons.key_outlined),
  person(CupertinoIcons.person, Icons.person_outline),
  filter(CupertinoIcons.slider_horizontal_3, Icons.filter_list),
  edit(CupertinoIcons.pencil, Icons.edit),
  undo(CupertinoIcons.arrow_uturn_left, Icons.undo),
  logs(CupertinoIcons.doc_text, Icons.article_outlined),
  deploy(CupertinoIcons.arrow_up_circle, Icons.rocket_launch_outlined),
  inbox(CupertinoIcons.tray, Icons.inbox_outlined),
  eye(CupertinoIcons.eye, Icons.visibility_outlined),
  eyeOff(CupertinoIcons.eye_slash, Icons.visibility_off_outlined),
  info(CupertinoIcons.info_circle, Icons.info_outline),
  calendar(CupertinoIcons.calendar, Icons.event_outlined),
  external(CupertinoIcons.arrow_up_right_square, Icons.open_in_new),
  image(CupertinoIcons.photo, Icons.image_outlined),
  pin(CupertinoIcons.pin, Icons.push_pin_outlined),
  pinFill(CupertinoIcons.pin_fill, Icons.push_pin),
  upload(CupertinoIcons.arrow_up_doc, Icons.upload_file),
  timer(CupertinoIcons.timer, Icons.timer_outlined),
  markUnread(CupertinoIcons.envelope_badge, Icons.mark_email_unread_outlined),
  markRead(CupertinoIcons.envelope_open, Icons.mark_email_read_outlined),
  dns(CupertinoIcons.list_bullet_indent, Icons.dns_outlined),
  bell(CupertinoIcons.bell, Icons.notifications_none);

  const EpIcon(this.cupertino, this.material);

  final IconData cupertino;
  final IconData material;

  IconData of(BuildContext context) => isCupertino(context) ? cupertino : material;
}

/// Platform-correct [Icon] for an [EpIcon] role.
class EpIconView extends StatelessWidget {
  const EpIconView(this.icon, {super.key, this.size, this.color, this.semanticLabel});

  final EpIcon icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) =>
      Icon(icon.of(context), size: size, color: color, semanticLabel: semanticLabel);
}
