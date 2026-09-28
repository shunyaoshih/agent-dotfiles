#!/usr/bin/env perl
# Minimal, ultra-fast hop.nvim-style 2-character jump for tmux copy mode.
use strict;
use warnings;

# tokyonight-night color palette (from tokyonight.nvim Hop & Search highlight groups)
my $ESC            = "\033";
my $RESET          = "${ESC}[0m";
my $HIDE_CURSOR    = "${ESC}[?25l";
my $SHOW_CURSOR    = "${ESC}[?25h";
my $HOP_UNMATCHED  = "${ESC}[38;2;84;92;126m";                  # HopUnmatched: fg=#545c7e
my $HOP_NEXT_KEY   = "${ESC}[1;38;2;255;0;124m";                # HopNextKey (1-char hint): bold fg=#ff007c
my $HOP_NEXT_KEY1  = "${ESC}[1;38;2;13;185;215m";               # HopNextKey1 (2-char 1st key): bold fg=#0db9d7
my $HOP_NEXT_KEY2  = "${ESC}[38;2;18;122;144m";                 # HopNextKey2 (2-char 2nd key): fg=#127a90
my $HOP_MATCH      = "${ESC}[38;2;192;202;245;48;2;61;89;161m"; # Search match: fg=#c0caf5 bg=#3d59a1

my @HINTS = split //, q{ntesaroibwfmuc,l'yzkhd"g.jxqpv};

binmode(STDOUT, ":utf8");
$| = 1;
$ENV{PATH} = ($ENV{PATH} // "/usr/bin:/bin") . ":/opt/homebrew/bin:/usr/local/bin";

my ($pane_id, $pane_width, $pane_height, $scroll_pos, $cur_x, $cur_y) = @ARGV;
if (!defined $pane_id || !defined $pane_height) {
    my $meta = `tmux display-message -p "#{pane_id}\t#{pane_width}\t#{pane_height}\t#{scroll_position}\t#{copy_cursor_x}\t#{copy_cursor_y}"`;
    chomp $meta;
    ($pane_id, $pane_width, $pane_height, $scroll_pos, $cur_x, $cur_y) = split /\t/, $meta, -1;
}
$scroll_pos = 0 unless defined $scroll_pos && $scroll_pos ne "";
$cur_x      = 0 unless defined $cur_x      && $cur_x ne "";
$cur_y      = 0 unless defined $cur_y      && $cur_y ne "";

my $start_line = -$scroll_pos;
my $end_line   = $pane_height - 1 - $scroll_pos;
open(my $cap_fh, "-|:utf8", "tmux", "capture-pane", "-p", "-t", $pane_id, "-S", $start_line, "-E", $end_line) or exit 1;
my @lines = map { s/\r?\n\z//r } <$cap_fh>;
close($cap_fh);
splice(@lines, $pane_height) if @lines > $pane_height;

sub char_width {
    my ($ch) = @_;
    my $cp = ord($ch);
    return 0 if ($cp >= 0x0300 && $cp <= 0x036F)
             || ($cp >= 0x1AB0 && $cp <= 0x1AFF)
             || ($cp >= 0x1DC0 && $cp <= 0x1DFF)
             || ($cp >= 0x20D0 && $cp <= 0x20FF)
             || ($cp >= 0xFE20 && $cp <= 0xFE2F);
    return 2 if $cp >= 0x1100 && (
                $cp <= 0x115F || $cp == 0x2329 || $cp == 0x232A
             || ($cp >= 0x2E80 && $cp <= 0xA4CF && $cp != 0x303F)
             || ($cp >= 0xAC00 && $cp <= 0xD7A3)
             || ($cp >= 0xF900 && $cp <= 0xFAFF)
             || ($cp >= 0xFE10 && $cp <= 0xFE19)
             || ($cp >= 0xFE30 && $cp <= 0xFE6F)
             || ($cp >= 0xFF00 && $cp <= 0xFF60)
             || ($cp >= 0xFFE0 && $cp <= 0xFFE6)
             || ($cp >= 0x1F300 && $cp <= 0x1FAFF)
             || ($cp >= 0x20000 && $cp <= 0x3FFFD));
    return 1;
}

sub visual_col {
    my ($line, $char_idx) = @_;
    my $w = 0;
    for my $c (split //, substr($line, 0, $char_idx)) {
        $w += char_width($c);
    }
    return $w;
}

sub draw_base {
    my $out = $HIDE_CURSOR . "${ESC}[2J";
    for my $y (0 .. $#lines) {
        my $row = $y + 1;
        $out .= "${ESC}[${row};1H${HOP_UNMATCHED}$lines[$y]${RESET}";
    }
    print $out;
}

sub find_matches {
    my ($query) = @_;
    my $smart_case = ($query =~ /[A-Z]/);
    my $q = $smart_case ? $query : lc($query);
    my @matches;
    for my $row (0 .. $#lines) {
        my $hay = $smart_case ? $lines[$row] : lc($lines[$row]);
        my $idx = 0;
        while ((my $pos = index($hay, $q, $idx)) != -1) {
            push @matches, [$row, $pos, visual_col($lines[$row], $pos)];
            $idx = $pos + 1;
        }
    }
    return @matches;
}

sub generate_labels {
    my ($count) = @_;
    my $n = scalar @HINTS;
    return @HINTS[0 .. $count - 1] if $count <= $n;
    my $k = int(($count - $n + $n - 2) / ($n - 1));
    $k = 1  if $k < 1;
    $k = $n if $k > $n;
    my @singles  = @HINTS[0 .. $n - $k - 1];
    my @prefixes = @HINTS[$n - $k .. $n - 1];
    my @doubles;
    for my $p (@prefixes) {
        for my $c (@HINTS) {
            push @doubles, $p . $c;
        }
    }
    my @all = (@singles, @doubles);
    return @all[0 .. $count - 1];
}

sub draw_hints {
    my ($label_map, $prefix) = @_;
    $prefix //= "";
    draw_base();
    my $out = "";
    for my $label (keys %$label_map) {
        next unless index($label, $prefix) == 0;
        my $rem = substr($label, length($prefix));
        next if $rem eq "";
        my ($row, $char_idx, $vcol) = @{$label_map->{$label}};
        my $line = $lines[$row];
        my $ch1  = substr($line, $char_idx, 1);
        my $ch2  = ($char_idx + 1 < length($line)) ? substr($line, $char_idx + 1, 1) : "";
        my $next_vcol = $vcol + char_width($ch1);
        my $r = $row + 1;
        my $c1 = $vcol + 1;
        my $c2 = $next_vcol + 1;

        if (length($rem) == 1) {
            $out .= "${ESC}[${r};${c1}H${HOP_NEXT_KEY}" . substr($rem, 0, 1) . $RESET;
            if ($ch2 ne "" && $next_vcol < $pane_width) {
                $out .= "${ESC}[${r};${c2}H${HOP_MATCH}${ch2}${RESET}";
            }
        } else {
            $out .= "${ESC}[${r};${c1}H${HOP_NEXT_KEY1}" . substr($rem, 0, 1) . $RESET;
            if ($next_vcol < $pane_width) {
                $out .= "${ESC}[${r};${c2}H${HOP_NEXT_KEY2}" . substr($rem, 1, 1) . $RESET;
            }
        }
    }
    print $out;
}

sub jump_to {
    my ($target_y, $target_char_idx) = @_;
    my $steps_x = 0;
    for my $c (split //, substr($lines[$target_y], 0, $target_char_idx)) {
        $steps_x++ if char_width($c) > 0;
    }

    my @cmds = ("tmux");
    my $dy = $target_y - $cur_y;
    if ($dy != 0) {
        push @cmds, "send-keys", "-t", $pane_id, "-X", "-N", abs($dy),
                    ($dy > 0 ? "cursor-down" : "cursor-up"), ";";
    }
    push @cmds, "send-keys", "-t", $pane_id, "-X", "start-of-line";
    if ($steps_x > 0) {
        push @cmds, ";", "send-keys", "-t", $pane_id, "-X", "-N", $steps_x, "cursor-right";
    }
    system(@cmds);

    # Repair if wrapped line caused start-of-line to walk up to previous row
    open(my $fh, "-|", "tmux", "display-message", "-p", "-t", $pane_id, "#{copy_cursor_y} #{copy_cursor_x}") or return;
    my $after = <$fh> // "";
    close($fh);
    chomp $after;
    my ($ay, $ax) = split / /, $after;
    return unless defined $ay && defined $ax;
    my $target_vcol = visual_col($lines[$target_y], $target_char_idx);
    my @fix;
    if ($ay != $target_y) {
        my $fdy = $target_y - $ay;
        push @fix, "send-keys", "-t", $pane_id, "-X", "-N", abs($fdy),
                   ($fdy > 0 ? "cursor-down" : "cursor-up");
    }
    if ($ax != $target_vcol) {
        push @fix, ";" if @fix;
        my $fdx = $target_vcol - $ax;
        push @fix, "send-keys", "-t", $pane_id, "-X", "-N", abs($fdx),
                   ($fdx > 0 ? "cursor-right" : "cursor-left");
    }
    system("tmux", @fix) if @fix;
}

# Put terminal into raw mode (zero-overhead ioctl on Linux & macOS, stty fallback elsewhere)
my ($saved_termios, $ioctl_set);
if ($^O eq "linux") {
    $saved_termios = "\0" x 60;
    if (ioctl(STDIN, 0x5401, $saved_termios)) { # TCGETS
        $ioctl_set = 0x5402;                   # TCSETS
        my ($if, $of, $cf, $lf, $line, @cc) = unpack("IIII C C32", $saved_termios);
        $if &= ~0x5ff;
        $of &= ~0x1;
        $lf &= ~0x807b;
        $cc[6] = 1; # VMIN
        $cc[5] = 0; # VTIME
        my $raw = pack("IIII C C32", $if, $of, $cf, $lf, $line, @cc) . substr($saved_termios, 49);
        ioctl(STDIN, $ioctl_set, $raw);
    } else {
        undef $saved_termios;
        system("stty", "raw", "-echo");
    }
} elsif ($^O eq "darwin") {
    $saved_termios = "\0" x 72;
    if (ioctl(STDIN, 0x40487413, $saved_termios)) { #TIOCGETA
        $ioctl_set = 0x80487414;                    #TIOCSETA
        my ($if, $of, $cf, $lf, @cc) = unpack("QQQQ C20", $saved_termios);
        $if &= ~0x3eb;
        $of &= ~0x1;
        $lf &= ~0x598;
        $cc[16] = 1; # VMIN
        $cc[17] = 0; # VTIME
        my $raw = pack("QQQQ C20", $if, $of, $cf, $lf, @cc) . substr($saved_termios, 52);
        ioctl(STDIN, $ioctl_set, $raw);
    } else {
        undef $saved_termios;
        system("stty", "raw", "-echo");
    }
} else {
    system("stty", "raw", "-echo");
}

sub cleanup {
    if (defined $saved_termios && defined $ioctl_set) {
        ioctl(STDIN, $ioctl_set, $saved_termios);
    } else {
        system("stty", "sane");
    }
    print $SHOW_CURSOR . $RESET;
}

END { cleanup(); }
$SIG{INT} = $SIG{TERM} = sub { exit 0; };

draw_base();

# 1. Read 2 target characters
my $query = "";
while (length($query) < 2) {
    my $ch = "";
    my $n = sysread(STDIN, $ch, 4);
    last if !$n;
    utf8::decode($ch);
    last if index($ch, "\x1b") != -1 || index($ch, "\x03") != -1 || index($ch, "\x04") != -1;
    if ($ch eq "\x7f" || $ch eq "\x08") {
        if (length($query) > 0) {
            substr($query, -1) = "";
            draw_base();
        }
        next;
    }
    for my $c (split //, $ch) {
        next if $c eq "\r" || $c eq "\n";
        $query .= $c;
        if (length($query) == 1) {
            my $out = "";
            for my $m (find_matches($query)) {
                my ($r, $idx, $vc) = @$m;
                my $row = $r + 1;
                my $col = $vc + 1;
                $out .= "${ESC}[${row};${col}H${HOP_MATCH}" . substr($lines[$r], $idx, 1) . $RESET;
            }
            print $out;
        }
        last if length($query) == 2;
    }
}
exit 0 if length($query) < 2;

# 2. Find all 2-character matches
my @matches = find_matches($query);
exit 0 if !@matches;
if (@matches == 1) {
    jump_to($matches[0][0], $matches[0][1]);
    exit 0;
}

# 3. Sort matches by distance from cursor and assign shortcut labels
my @ranked = sort {
    (($a->[2] - $cur_x) ** 2 + (2 * ($a->[0] - $cur_y)) ** 2)
    <=>
    (($b->[2] - $cur_x) ** 2 + (2 * ($b->[0] - $cur_y)) ** 2)
} @matches;
splice(@ranked, @HINTS ** 2) if @ranked > @HINTS ** 2;
my @labels = generate_labels(scalar @ranked);
my %label_map;
@label_map{@labels} = @ranked;

draw_hints(\%label_map, "");

# 4. Read shortcut key(s) and jump
my $typed = "";
while (1) {
    my $ch = "";
    my $n = sysread(STDIN, $ch, 4);
    last if !$n;
    utf8::decode($ch);
    last if index($ch, "\x1b") != -1 || index($ch, "\x03") != -1 || index($ch, "\x04") != -1;
    if (($ch eq "\x7f" || $ch eq "\x08") && length($typed) > 0) {
        substr($typed, -1) = "";
        draw_hints(\%label_map, $typed);
        next;
    }
    $typed .= substr($ch, 0, 1);
    if (exists $label_map{$typed}) {
        my ($row, $char_idx) = @{$label_map{$typed}};
        jump_to($row, $char_idx);
        last;
    }
    my $has_prefix = 0;
    for my $k (keys %label_map) {
        if (index($k, $typed) == 0) {
            $has_prefix = 1;
            last;
        }
    }
    if ($has_prefix) {
        draw_hints(\%label_map, $typed);
    } else {
        last;
    }
}
