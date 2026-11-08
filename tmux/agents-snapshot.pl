#!/usr/bin/perl
# Print one tab-separated row per live Claude Code pane on this tmux server,
# what needs you first:
#
#   PANE_ID  STATE  LOCATION  AGENT  TITLE  DISPLAY
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
# AGENT changes whenever the pane gets another agent or its status changes, so
# the dashboard can tell that a row is out of date before it sends keys. TITLE is
# the pane's title, and DISPLAY the colored text to show. This is the only part
# of the dashboard that knows where agent state comes from, or what an agent's
# screen looks like:
#
#   agents-snapshot.pl approval PANE_ID   the prompt the agent is waiting on
#   agents-snapshot.pl input PANE_ID      whether a reply can go in its input box
#
# approval prints KEY<tab>CHOICE, the key that picks the prompt's "1. Yes" and
# that option's text, then the prompt as it is on screen. input prints nothing.
# If they can't, both print why, worded to follow the agent's location, and exit
# 1.
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

exit approval($ARGV[1]) if ($ARGV[0] // '') eq 'approval';
exit input($ARGV[1])    if ($ARGV[0] // '') eq 'input';

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
		id      => join('/', $session->{pid}, $session->{sessionId} // '', $updated),
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
		agent    => $agent->{id},
		title    => $title,
	};
}
close $panes;
@rows = sort { $rank{ $a->{state} } <=> $rank{ $b->{state} } || $b->{updated} <=> $a->{updated} } @rows;

my $location_width = max(map { width($_->{location}) } @rows);
my $title_width    = min(40, max(map { width($_->{title}) } @rows));

for my $row (@rows) {
	my ($mark, $state_color, $text_color) = @{ $style{ $row->{state} } };
	my $display = sprintf("%s%s %-10s\e[0m  %s%s  %s  %3s\e[0m",
		$state_color, $mark, $row->{state}, $text_color,
		fit($row->{location}, $location_width),
		fit($row->{title},    $title_width),
		$row->{state} eq 'working' ? 'now' : age($row->{updated}));
	print join("\t", $row->{pane}, $row->{state}, $row->{location}, $row->{agent}, $row->{title},
		$display), "\n";
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
# bottom. These read the visible screen, without trailing blank lines.
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
sub fail  { print "$_[0]\n"; return 1 }

sub approval {
	my @lines = screen($_[0]) or return fail("is gone");
	my ($top) = reverse rules(@lines);
	return fail("has no prompt on its screen") unless defined $top;
	my @prompt = @lines[$top + 1 .. $#lines];
	my ($choice) = map { /^\s*(?:❯\s*)?(1\.\s+Yes\b.*?)\s*$/ ? $1 : () } @prompt;
	return fail('has no "1. Yes" in its prompt to approve') unless $choice;
	print "1\t$choice\n", map { "$_\n" } @prompt;
	return 0;
}

# An empty input box shows a dim placeholder at most. A box that isn't the last
# thing between rules means a menu or dialog is open, where a reply's Enter would
# pick an option.
sub input {
	my @lines = screen($_[0], '-e') or return fail("is gone");
	my ($top, $bottom) = (rules(@lines))[-2, -1];
	return fail("isn't showing its input box, so a menu or dialog may be open")
		unless defined $top && $bottom > $top + 1 && plain($lines[$top + 1]) =~ /^❯/;
	(my $text = $lines[$top + 1]) =~ s/\e\[2m.*?\e\[(?:0|22)?m//g;
	return fail("has unsent text in its input box")
		if $bottom > $top + 2 || plain($text) =~ /^❯\s*\S/;
	return 0;
}
