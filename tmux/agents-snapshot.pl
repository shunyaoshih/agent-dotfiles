#!/usr/bin/perl
# Print one tab-separated row per live Claude Code pane on this tmux server:
#
#   PANE_ID  STATE  LOCATION  DISPLAY
#
# STATE is "working" (busy, so new input is queued), "background" (its turn ended
# but a background shell is still running, so it can take new input) or "idle".
# LOCATION is session:window, plus .pane when the window has several panes.
# DISPLAY is the colored text to show. This is the only part of the dashboard
# that knows where agent state comes from.
#
# Claude Code keeps one <pid>.json per process in ~/.claude/sessions. Its tmux
# field looks like "corner:@209.%209"; only the %id is used, because the session
# name in it goes stale after a rename. These files are internal to Claude Code
# and could change. The directory also holds .key files, which are never opened.
use strict;
use warnings;
use utf8;
use JSON::PP ();

binmode STDOUT, ':utf8';

my $sessions = ($ENV{CLAUDE_CONFIG_DIR} // "$ENV{HOME}/.claude") . '/sessions';

# Colors from the Tokyo Night palette: state marker and row text.
my %style = (
	working    => ['●', "\e[38;2;122;162;247m", "\e[38;2;192;202;245m"],
	background => ['◐', "\e[38;2;187;154;247m", "\e[38;2;192;202;245m"],
	idle       => ['○', "\e[38;2;115;122;162m", "\e[38;2;169;177;214m"],
);

# Claude Code's status => state. Anything else shows as idle.
my %states = (busy => 'working', shell => 'background');

# Pane id => the live agent in it. A file can outlive its process if Claude Code
# didn't exit cleanly, so check the pid. kill 0 fails with EPERM only if the
# process exists but belongs to someone else.
my %agents;
opendir(my $dir, $sessions) or exit 0;
for my $file (grep { /\.json\z/ } readdir $dir) {
	open(my $fh, '<', "$sessions/$file") or next;
	my $session = eval { JSON::PP::decode_json(do { local $/; <$fh> }) };
	next unless ref $session eq 'HASH' && $session->{pid};
	my ($pane) = ($session->{tmux} // '') =~ /(%\d+)\z/ or next;
	next unless kill(0, $session->{pid}) || $!{EPERM};
	my $updated = $session->{statusUpdatedAt} // 0;
	next if $agents{$pane} && $agents{$pane}{updated} >= $updated;
	$agents{$pane} = { status => $session->{status} // '', updated => $updated };
}

# -u because tmux replaces non-ASCII output with _ if the locale isn't UTF-8.
open(my $panes, '-|', 'tmux', '-u', 'list-panes', '-a', '-F',
	join("\t", map { "#{$_}" } qw(pane_id session_name window_index pane_index window_panes pane_title)))
	or exit 1;

# A window linked into several sessions lists its panes once per session.
my (%seen, @rows);
while (my $line = <$panes>) {
	chomp $line;
	utf8::decode($line);
	my ($pane, $session, $window, $index, $count, $title) = split /\t/, $line, 6;
	next if $seen{$pane}++;
	my $agent = $agents{$pane} or next;
	$title //= '';
	$title =~ s/^[^\p{L}\p{N}]+//;    # Claude Code's leading ✳ or spinner
	push @rows, {
		pane     => $pane,
		state    => $states{ $agent->{status} } // 'idle',
		updated  => $agent->{updated},
		location => "$session:$window" . ($count > 1 ? ".$index" : ''),
		title    => $title,
	};
}
close $panes;

my $location_width = max(map { width($_->{location}) } @rows);
my $title_width    = min(40, max(map { width($_->{title}) } @rows));

for my $row (@rows) {
	my ($mark, $state_color, $text_color) = @{ $style{ $row->{state} } };
	my $display = sprintf("%s%s %-10s\e[0m  %s%s  %s  %3s\e[0m",
		$state_color, $mark, $row->{state}, $text_color,
		fit($row->{location}, $location_width),
		fit($row->{title},    $title_width),
		$row->{state} eq 'working' ? 'now' : age($row->{updated}));
	print join("\t", $row->{pane}, $row->{state}, $row->{location}, $display), "\n";
}

sub max { my $m = 0; for (@_) { $m = $_ if $_ > $m } $m }
sub min { $_[0] < $_[1] ? $_[0] : $_[1] }

# Time since a millisecond timestamp, as now, 19m, 6h or 3d. There are no
# seconds, so a row only changes when there's something new to show.
sub age {
	return '' unless $_[0];
	my $seconds = time - $_[0] / 1000;
	return $seconds < 60 ? 'now'
		: $seconds < 3600  ? int($seconds / 60) . 'm'
		: $seconds < 86400 ? int($seconds / 3600) . 'h'
		:                    int($seconds / 86400) . 'd';
}

# Terminal columns taken by a string: titles can hold CJK and combining marks.
sub width {
	my $width = 0;
	$width += char_width($_) for split //, $_[0];
	return $width;
}

sub char_width { $_[0] =~ /[\p{Mn}\p{Me}\p{Cf}]/ ? 0 : $_[0] =~ /[\p{EA=W}\p{EA=F}]/ ? 2 : 1 }

# Pad or truncate a string to exactly this many columns.
sub fit {
	my ($text, $columns) = @_;
	if (width($text) > $columns) {
		my ($fitted, $used) = ('', 0);
		for my $char (split //, $text) {
			last if $used + char_width($char) > $columns - 1;
			$fitted .= $char;
			$used   += char_width($char);
		}
		$text = "$fitted…";
	}
	return $text . ' ' x ($columns - width($text));
}
