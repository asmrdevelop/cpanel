package Cpanel::Locale::Utils::Tool;

# cpanel - Cpanel/Locale/Utils/Tool.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule    ();
use IO::Interactive::Tiny ();

use Cpanel::Logger               ();
use Cpanel::DataStore            ();
use Cpanel::Locale::Utils::Queue ();
use Cpanel::Locale::Utils        ();

sub import {
    my $caller = caller();
    no strict 'refs';    ## no critic(ProhibitNoStrict) Symbolic refs for exporting subs
    *{ $caller . '::style' }  = \&style;
    *{ $caller . '::indent' } = \&indent;
    return;
}

my $interactive;

sub is_interactive {
    if ( !defined $interactive ) {
        $interactive = ( ( @ARGV > 1 && $ARGV[1] eq '-' && -t *STDOUT ) || IO::Interactive::Tiny::is_interactive() ) ? 1 : 0;
    }
    return $interactive if $interactive;
    return;
}

sub pid_file_check {
    Cpanel::LoadModule::load_perl_module('Unix::PID');
    Unix::PID->new()->pid_file('/var/run/locale_tool.pid') or die <<"END_PIDFILE";
Sorry, it looks like $0 is already running on this system.*

Until it is finished you won’t be able to run this command.

* The PID in /var/run/locale_tool.pid is still running.
END_PIDFILE
    return;
}

sub prompt_next {
    if ( is_interactive() ) {
        Cpanel::LoadModule::load_perl_module('IO::Prompt');
        IO::Prompt::prompt( "[Hit enter for next]", "-tty", "-newline" => "" );
    }
    return;
}

sub prompt_yes_no {
    my ($question) = @_;
    $question ||= "Yes or no?";

    $question =~ s/\s*$/ /;

    if ( is_interactive() ) {
        return IO::Prompt::prompt( $question, "-tty", "-newline" => "", "-yes_no" );
    }

    return;    # we should default to no just in case they, for example, pipe a command that requires an answer
}

sub prompt_choice {
    my ( $question, $choice_ar, $default ) = @_;

    $question =~ s/\s*$//;

    my $stand_out = "\e[1;107;30m";
    my @chars;
    if ( is_interactive() ) {
        die "At least one choice needs to be given." if !@{$choice_ar};

        for my $item ( @{$choice_ar} ) {
            die "'char' needs to be at least one character long." if !exists $item->{'char'} || length( $item->{'char'} ) == 0;
            die "'text' needs to be given."                       if !exists $item->{'text'} || length( $item->{'text'} ) == 0;

            my $text = $item->{'text'};
            push @chars, $item->{'char'};
            if ( $text =~ m{\Q$item->{char}\E} ) {
                $text =~ s{(\Q$item->{char}\E)}{$stand_out$1\e[0m)};
            }
            else {
                $text = "$stand_out$item->{char}\e[0m) $text";
            }

            $question .= " $text";
        }

        my $pipe_delim = join( '|',  map { qr/\Q$_\E/ } @chars );
        my $or_list    = join( ", ", @chars );
        if ( @chars >= 3 ) {
            $or_list =~ s{, \Q$chars[-1]\E$}{, or $chars[-1]};
        }
        else {
            $or_list =~ s{, \Q$chars[-1]\E$}{ or $chars[-1]};
        }

        my $def_text = defined $default ? "[$default] " : '';                                                                                                                                                  # match the style of prompt()'s -d option
        my $choice   = IO::Prompt::prompt( $question . " > ", "-tty", "-r", { "$question (Please enter $or_list) > $def_text" => qr/\A($pipe_delim)\z/i }, ( defined $default ? ( "-d", $default ) : () ) );

        # Handle <esc>:
        # return $default if $pres eq "\x1b" || $pres eq "\x{001b}";
        $choice = {} if !ref($choice);

        return $choice->{'value'} || $default;
    }

    return;
}

sub prompt_menu {
    my ( $question, $menu_ref, $default ) = @_;

    $question =~ s/\s*$/\n/;

    if ( is_interactive() ) {

        # -raw and -default does not work as described in the POD for -menu
        my $pres = IO::Prompt::prompt( $question, '-tty', '-menu', $menu_ref );

        # Handle <esc>:
        # return $default if $pres eq "\x1b" || $pres eq "\x{001b}";
        $pres = {} if !ref($pres);

        return $pres->{'value'} || $default;
    }

    return $default if defined $default;
    return;
}

sub indent {
    my ($str) = @_;
    my $cnt = defined $str ? int($str) : 1;
    $cnt ||= 1;
    return '   ' x $cnt;
}

sub nyi {
    print "Not yet implemented";
    return;
}

my %style = (
    'bold'      => "\e[1m",
    'good'      => "\e[40;32m✔ ",
    'info'      => "\e[44;37m",      # ℹ\xe2\x83\x9d
    'warn'      => "\e[40;33m⚠ ",
    'error'     => "\e[40;31m‼ ",    #  ☠ ☢ ☣ ☹
    'highlight' => "\e[47;30m",
);

sub style {
    my ( $class, $msg ) = @_;
    $msg = $class unless defined $msg;
    return is_interactive() && exists $style{$class} ? "$style{$class}$msg\e[0m" : ( !is_interactive() && $class eq 'highlight' ? qq{'$msg'} : $msg );
}

sub walk_hash {
    my ( $hr, $handler, $handler_does_prompt ) = @_;

    my $current = 0;
    my $total   = keys %{$hr};
    if ( !$total ) {
        print "Nothing to report.\n";
        return;
    }

  KEY:
    for my $key ( sort keys %{$hr} ) {
        print "\n------------------------\n" unless ++$current == 1;
        my $disp_key = $key;
        if ( is_interactive() ) {
            my $visible_newline = "\xe2\x90\xa4";    # \x{2424} SYMBOL FOR NEWLINE
            while ( $disp_key =~ m{\n(?:\n$visible_newline)*\z} ) { $disp_key =~ s{\n((?:\n$visible_newline)*)\z}{\n$visible_newline$1}g; }
        }

        if ( $disp_key eq '' ) {
            $disp_key = "\xe2\x90\xa2";              # \x{2422} BLANK SYMBOL
        }

        print "$current of $total: " . style( "highlight", $disp_key ) . "\n";
        my $rc = $handler->( $key, $hr->{$key} );
        if ( $rc && $rc == 0 ) {
            last KEY;
        }
        prompt_next() unless $handler_does_prompt;
    }
    print "\n";
    return;
}

sub ensure_is_in_queue {
    my @new_phrases = @_;

    Cpanel::DataStore::edit_datastore(
        Cpanel::Locale::Utils::Queue::get_pending_file(),
        sub {
            my ($hr) = @_;
            for my $np (@new_phrases) {
                $hr->{$np} = '';
            }
            return 1;    # true means to save the new ref to disk
        }
    ) || die "Could not add new phrases to pending queue: $!";
    system('/usr/local/cpanel/build-tools/tidy_pending');
    return;
}

sub get_git_starting_branch {
    return undef if $Cpanel::Locale::Utils::i_am_the_compiler;
    return undef unless Cpanel::Logger::is_sandbox();

    my $starting_branch = `git rev-parse --abbrev-ref HEAD 2>&1`;
    return if !defined $starting_branch;
    chomp($starting_branch);

    # If on a detached head, use the tree-ish instead of "HEAD"
    if ( $starting_branch eq 'HEAD' ) {
        $starting_branch = `git rev-parse HEAD`;
        chomp($starting_branch);
    }

    return $starting_branch;
}

my @session_sanity = (
    {
        'get_state' => \&get_git_starting_branch,
        'value'     => undef,
        'problem'   => sub {
            my ( $value_before, $value_now ) = @_;
            return "Your git branch was “$value_before” but now it is “$value_now”.";
        },
        'prompt' => sub {
            my ( $check, $value_before, $value_now ) = @_;

            my $quit = 'Quit immediately without doing anything further. ';    # yes, we want a trailing space here

            if ( defined $ARGV[0] && $ARGV[0] eq 'edit' ) {
                $quit .= style( 'highlight', 'Any edits will be discarded.' );
            }
            elsif ( defined $ARGV[0] && $ARGV[0] eq 'queue' ) {
                $quit .= style( 'highlight', 'Nothing will be queued.' );
            }
            else {
                $quit .= style( 'highlight', 'Any changes not written to disk will be lost.' );
            }

            my $res = Cpanel::Locale::Utils::Tool::prompt_menu(
                "\n" . style( 'warn', $check->{'problem'}->( $value_before, $value_now ) ) . "\n\nThat may or may not be a problem depending on your circumstances.\n\nYour available options are:",
                [
                    "Stay on “$value_now” and continue.",
                    "Switch back to “$value_before” then continue.",
                    $quit,
                ],
            );

            $res = "" if !defined $res;    # hide uninit warnings (so the error can be seen) when run non-interactively and the branch changes

            return 1 if $res =~ m/^Stay/;
            return   if $res =~ m/^Quit/;

            if ( $res =~ m/^Switch/ ) {
                system( 'git', 'checkout', $value_before );

                my $current_branch = $check->{'get_state'}->() || '';
                if ( $current_branch ne $value_before ) {
                    print style( 'error', "Sorry, it appears that the checkout of “$value_before” did not work. Please try again." ) . "\n";
                    return $check->{'prompt'}->( $check, $value_before, $value_now );

                }

                $check->{'value'} = $current_branch;
                return 1;
            }
            else {
                print style( 'error', "Sorry, I don’t know how to handle “$res”. Please try again." ) . "\n";
                return $check->{'prompt'}->( $check, $value_before, $value_now );
            }

        },
    },
);

my $session_sanity_initialized = 0;

sub session_sanity_init {

    # This check only makes sense when running individual sub commands:
    unless ( defined $ARGV[0] && $ARGV[0] eq 'shell' ) {

        # Calling session_sanity_init()  a second time could mask changes and render the next session_sanity_check() call useless.
        # That means this situation is programmer error so we die to alert the programmer to the problem.
        if ($session_sanity_initialized) {
            require Cpanel::Carp;
            die Cpanel::Carp::safe_longmess('session_sanity_init() should only be called once per session');
        }
    }

    for my $check (@session_sanity) {
        $check->{'value'} = $check->{'get_state'}->();
    }

    $session_sanity_initialized++;
    return;
}

sub session_sanity_check {

    if ( !$session_sanity_initialized ) {

        # We could call session_sanity_init() here but then the check below would be moot (i.e. the values would all match).
        # That means this situation is programmer error so we die to alert the programmer to the problem.
        die 'session_sanity_check() was called before session_sanity_init()';
    }

    for my $check (@session_sanity) {
        my $prev_value = $check->{'value'} || '';
        $check->{'value'} = $check->{'get_state'}->() || '';    # same as session_sanity_init()
        if ( $prev_value ne $check->{'value'} ) {

            # default prompt
            $check->{'prompt'} ||= sub {
                my ( $check, $value_before, $value_now ) = @_;
                return 1 if prompt_yes_no( $check->{'problem'}->( $value_before, $value_now ) . ' Is it safe to continue?' );
                return;
            };

            if ( !$check->{'prompt'}->( $check, $prev_value, $check->{'value'} ) ) {
                print "Exiting per your request …\n";
                exit;
            }
        }
    }
    return;
}

sub get_counts_hr {
    return { 'total' => 0, 'good' => 0, 'warn' => 0, 'error' => 0 };
}

sub display_counts_hr_summary {
    my ($counts) = @_;

    print style( "info", "Summary" ) . "\n";
    print indent() . "Phrase Count: $counts->{'total'}\n";

    if ( $counts->{'total'} ) {
        print indent(2) . style( "good",  "Passed" ) . ": $counts->{'good'}\n";
        print indent(2) . style( "warn",  "Warnings" ) . ": $counts->{'warn'}\n";
        print indent(2) . style( "error", "Violations" ) . ": $counts->{'error'}\n";
    }
    return;
}

sub do_pre_walk_summary {
    my ($phrases_hr) = @_;

    my $counts = get_counts_hr();

    for my $phrase ( keys %{$phrases_hr} ) {
        $counts->{'total'}++;
        $counts->{ $phrases_hr->{$phrase}[0]{'cpanel:checker:style'} }++;
    }

    display_counts_hr_summary($counts);

    print "------------------------\n";    # we should probably have a function to do these <hr/>-type separators
    return;
}

sub shell_escape_bn {
    my ($string) = @_;
    $string =~ s/([\[\]])/\\$1/g;
    return $string;
}

1;
