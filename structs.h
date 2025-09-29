#pragma once

struct frame {
  const char *text;
  int len;
  int start_offset;
  int end_offset;
};

enum instruction {
  do_nothing,
  go_left,
  go_down,
  go_up,
  go_right,
  make_into_hole,
  insert_before,
  insert_after,
  remove_cursor_node
};
