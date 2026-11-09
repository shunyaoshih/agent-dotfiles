#!/usr/bin/perl
# Print one tab-separated row per live Claude Code pane on this tmux server,
# what needs you first:
#
#   PANE_ID  STATE  LOCATION  DISPLAY
#
# STATE is, in the order rows are sorted (most recently changed first within
# each):
#   blocked     waiting on you: a permission prompt, a question or another dialog
#   done        its turn ended since you last looked at its pane
#   working     busy, so new input is queued
#   background  its turn ended but a background shell is still running, so it
#               can take new input
#   idle        nothing new to see
# LOCATION is session:window, plus .pane when the window has several panes.
# DISPLAY is the colored text to show. This is the only part of the dashboard
# that knows where agent state comes from, or what an agent's screen looks like:
#
#   agents-snapshot.pl transcript PANE_ID   its history, without the input box
#   agents-snapshot.pl prompts PANE_ID      where in that your prompts are
#
# Claude Code keeps one <pid>.json per process in ~/.claude/sessions. Its tmux
# field looks like "corner:@209.%209"; only the %id is used, because the session
# name in it goes stale after a rename. Its status is "waiting" from the moment a
# prompt or dialog opens until it's answered or cancelled, which Claude Code's own
# session list also calls blocked. These files are internal to Claude Code and
# could change. The directory also holds .key files, which are never opened.
#
# For done, tmux.conf's focus hooks record in @agents_seen when each pane was last
# looked at.
use strict;
use warnings;
use utf8;
use JSON::PP ();

binmode STDOUT, ':utf8';

exit transcript($ARGV[1]) if ($ARGV[0] // '') eq 'transcript';
exit prompts($ARGV[1])    if ($ARGV[0] // '') eq 'prompts';

my $sessions = ($ENV{CLAUDE_CONFIG_DIR} // "$ENV{HOME}/.claude") . '/sessions';

# Colors from the Tokyo Night palette: state marker and row text.
my %style = (
	blocked    => ['⚠', "\e[38;2;247;118;142m", "\e[38;2;192;202;245m"],
	done       => ['◆', "\e[38;2;115;218;202m", "\e[38;2;192;202;245m"],
	working    => ['●', "\e[38;2;122;162;247m", "\e[38;2;192;202;245m"],
	background => ['◐', "\e[38;2;187;154;247m", "\e[38;2;192;202;245m"],
	idle       => ['○', "\e[38;2;115;122;162m", "\e[38;2;169;177;214m"],
);
my %rank = (blocked => 0, done => 1, working => 2, background => 3, idle => 4);

# Claude Code's status => state. Anything else shows as idle.
my %states = (waiting => 'blocked', busy => 'working', shell => 'background');

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
	$agents{$pane} = {
		status  => $session->{status} // '',
		updated => $updated,
		cwd     => $session->{cwd} // '',
	};
}

# -u because tmux replaces non-ASCII output with _ if the locale isn't UTF-8.
open(my $panes, '-|', 'tmux', '-u', 'list-panes', '-a', '-F',
	join("\t", map { "#{$_}" } qw(pane_id session_name window_index pane_index window_panes
		pane_active window_active_clients @agents_seen pane_title)))
	or exit 1;

# A window linked into several sessions lists its panes once per session.
my (%seen, @rows);
while (my $line = <$panes>) {
	chomp $line;
	utf8::decode($line);
	my ($pane, $session, $window, $index, $count, $active, $viewers, $seen_at, $title) =
		split /\t/, $line, 9;
	next if $seen{$pane}++;
	my $agent = $agents{$pane} or next;
	my $state = $states{ $agent->{status} } // 'idle';
	# A pane a client is showing counts as looked at now, so nothing turns done
	# while you watch it. @agents_seen is in whole seconds, so a turn that ends in
	# the same second you leave counts as done rather than being missed.
	$state = 'done' if ($state eq 'idle' || $state eq 'background')
		&& !($active && $viewers) && $seen_at ne ''
		&& int($agent->{updated} / 1000) >= $seen_at;
	$title //= '';
	$title =~ s/^[^\p{L}\p{N}]+//;    # Claude Code's leading ✳ or spinner
	push @rows, {
		pane     => $pane,
		state    => $state,
		updated  => $agent->{updated},
		location => "$session:$window" . ($count > 1 ? ".$index" : ''),
		title    => $title,
		place    => place($agent->{cwd}),
	};
}
close $panes;
@rows = sort { $rank{ $a->{state} } <=> $rank{ $b->{state} } || $b->{updated} <=> $a->{updated} } @rows;

my $location_width = max(map { width($_->{location}) } @rows);
my $title_width    = min(40, max(map { width($_->{title}) } @rows));
my $place_width    = min(36, max(map { width($_->{place}) } @rows));

# The marker's color says the state, so the word itself isn't shown.
for my $row (@rows) {
	my ($mark, $state_color, $text_color) = @{ $style{ $row->{state} } };
	my $display = sprintf("%s%s\e[0m %s%s  %s  \e[38;2;115;122;162m%s\e[0m  %s%3s\e[0m",
		$state_color, $mark, $text_color,
		fit($row->{location}, $location_width),
		fit($row->{title},    $title_width),
		fit($row->{place},    $place_width),
		$row->{state} eq 'working' ? $state_color : $text_color,
		$row->{state} eq 'working' ? 'now' : age($row->{updated}));
	print join("\t", $row->{pane}, $row->{state}, $row->{location}, $display), "\n";
}

# Where the agent was started, with ~ for home, and its git branch, read from
# .git/HEAD rather than by running git, which would take a process per row every
# 2 seconds. In a worktree, .git is a file that names the real git directory.
sub place {
	my ($cwd) = @_;
	return '' if $cwd eq '';
	(my $place = $cwd) =~ s/^\Q$ENV{HOME}\E(?=\/|\z)/~/;
	for (my $dir = $cwd; $dir ne ''; $dir =~ s/\/[^\/]*\z//) {
		my $git = "$dir/.git";
		next unless -e $git;
		if (-f $git && open(my $fh, '<', $git)) {
			my ($path) = (<$fh> // '') =~ /^gitdir: (.+)/ or last;
			$git = $path =~ m{^/} ? $path : "$dir/$path";
		}
		open(my $fh, '<', "$git/HEAD") or last;
		my $head = <$fh> // '';
		my $branch = $head =~ /^ref: refs\/heads\/(.+)/ ? $1 : substr($head, 0, 7);
		return "$place · $branch";
	}
	return $place;
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

# Claude Code draws a full-width rule of ─ above its input box and below it, and
# a dialog replaces both with one rule above the dialog, which runs to the
# bottom. screen captures a pane without trailing blank lines.
sub screen {
	my ($pane, @flags) = @_;
	open(my $fh, '-|', 'tmux', '-u', 'capture-pane', '-p', @flags, '-t', $pane) or return;
	my @lines = <$fh>;
	close $fh or return;
	chomp @lines;
	utf8::decode($_) for @lines;
	pop @lines while @lines && $lines[-1] =~ /^\s*$/;
	return @lines;
}

sub plain { (my $text = $_[0]) =~ s/\e\[[0-9;:]*m//g; return $text }
sub rules { my @lines = @_; return grep { plain($lines[$_]) =~ /^─{20,}\s*$/ } 0 .. $#lines }

# The pane's history and screen in color, down to the line above the input box.
# The box, its rules and the hints under it are the same on every agent, and once
# wrapped to the preview's width they turn into rows of rules. A dialog is kept,
# since it's what the agent is waiting on.
sub transcript_lines {
	my @lines = screen($_[0], '-e', '-S', '-') or return;
	my ($top) = (rules(@lines))[-2];
	if (defined $top && plain($lines[$top + 1]) =~ /^❯/) {
		splice @lines, $top;
		pop @lines while @lines && plain($lines[-1]) =~ /^\s*$/;
	}
	return @lines;
}

sub transcript {
	my @lines = transcript_lines($_[0]) or return 1;
	print map { "$_\n" } @lines;
	return 0;
}

# The transcript's line count, then the number of each line where you wrote to
# the agent, the same lines tmux.conf's [ and ] jump to in copy mode.
sub prompts {
	my @lines = transcript_lines($_[0]) or return 1;
	print scalar(@lines), "\n", map { plain($lines[$_]) =~ /^❯ / ? $_ + 1 . "\n" : () } 0 .. $#lines;
	return 0;
}
