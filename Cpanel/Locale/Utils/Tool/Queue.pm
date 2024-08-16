package Cpanel::Locale::Utils::Tool::Queue;

# cpanel - Cpanel/Locale/Utils/Tool/Queue.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Locale::Utils::Tool;
use Cpanel::Locale::Utils::Tool::Find ();

sub subcmd {    ## no critic(ProhibitExcessComplexity)
    my ( $app, $resource, @args ) = @_;

    if ( $resource eq '-' ) {
        print "Processing files provided via STDIN …\n";
        $resource = [ grep { !m{(^|/)locale/queue/pending\.yaml$} } <STDIN> ];
        chomp( @{$resource} );
    }
    my $find_opts = { 'return_hash' => 1, 'passed' => 1, 'warnings' => 1, 'violations' => 1, 'verbose_with_return_hash' => 1 };
    my $opts      = { 'interactive' => 0, 'dryrun' => 0 };
    for my $flag (@args) {
        die "'queue' does not know about '$flag'" if $flag !~ m/^--(?:interactive|verbose|release-harvest|dryrun|no-git-check|devel)$/;
        if ( $flag eq '--interactive' ) {
            $opts->{'interactive'} = 1;
        }
        elsif ( $flag eq '--verbose' ) {
            $find_opts->{'verbose'} = 1;
        }
        elsif ( $flag eq '--release-harvest' ) {
            $find_opts->{'release-harvest'} = 1;
        }
        elsif ( $flag eq '--dryrun' ) {
            $opts->{'dryrun'} = 1;
        }
        elsif ( $flag eq '--no-git-check' ) {
            $find_opts->{'no-git-check'} = 1;
        }
        elsif ( $flag eq '--devel' ) {
            $opts->{'devel'}        = 1;
            $find_opts->{'verbose'} = 1;
        }
    }

    Cpanel::Locale::Utils::Tool::pid_file_check();
    Cpanel::Locale::Utils::Tool::session_sanity_init();
    _abort_if_repo_has_staged() if $opts->{'devel'};
    my %new_phrases = Cpanel::Locale::Utils::Tool::Find::run( $resource, $find_opts );
    my %report;
    my %skipped;

    for my $phrase ( sort keys %new_phrases ) {
        my $result = $new_phrases{$phrase}->[0]{'cpanel:checker:result'};
        if ( $result->get_violation_count() || ( !$opts->{'devel'} && !$opts->{'interactive'} && $result->get_warning_count() ) ) {

            # If release-harvest flag was passed and we didn't get a violation, skip it so it's added to the queue
            if ( $find_opts->{'release-harvest'} && $result->{'violation_count'} == 0 ) {
                print style( "info", "Adding the following phrase without violations due to --release-harvest flag: $phrase" ) . "\n";
                next;
            }
            $report{$phrase} = delete $new_phrases{$phrase};
            next;
        }
    }

    if ( $opts->{'interactive'} ) {
        my %untraversed = %new_phrases;
        Cpanel::Locale::Utils::Tool::walk_hash(
            \%new_phrases,
            sub {
                my ( $phrase, $instances ) = @_;

                my $result = $instances->[0]{'cpanel:checker:result'};
                if ( $result->get_violation_count() ) {
                    $report{$phrase} = delete $new_phrases{$phrase};
                    return;
                }

                Cpanel::Locale::Utils::Tool::session_sanity_check();
                Cpanel::Locale::Utils::Tool::Find::walk_hash_output( $phrase, $instances, $find_opts );

                my $choice_char = Cpanel::Locale::Utils::Tool::prompt_choice(
                    'Do you want to add it to the queue?',
                    [
                        {
                            'char' => 'y',
                            'text' => 'yes',
                        },
                        {
                            'char' => 'n',
                            'text' => 'no',
                        },
                        {
                            'char' => 'q',
                            'text' => 'save and quit editing',
                        },
                    ]
                );
                if ( $choice_char eq 'n' ) {
                    $skipped{$phrase} = delete $new_phrases{$phrase};
                    delete $untraversed{$phrase};
                }
                elsif ( $choice_char eq 'q' ) {
                    @skipped{ keys %untraversed } = delete @new_phrases{ keys %untraversed };
                    return '0E0';
                }
                else {
                    delete $untraversed{$phrase};
                }
            },
            1,
        );
    }

    if ( keys %new_phrases ) {
        if ( !$opts->{'dryrun'} ) {
            Cpanel::Locale::Utils::Tool::session_sanity_check();
            _abort_if_repo_has_staged() if $opts->{'devel'};
            Cpanel::Locale::Utils::Tool::ensure_is_in_queue( keys %new_phrases );    # die()s if there is a problem
        }
    }

    if ( keys %report ) {
        if ( $opts->{'interactive'} && Cpanel::Locale::Utils::Tool::is_interactive() ) {
            IO::Prompt::prompt( "[Press enter to continue to problem report]", "-tty", "-clear" );    # IO::Prompt brought in via Cpanel::Locale::Utils::Tool
        }
        print style( "info", "Problem Report:" ) . "\n";

        Cpanel::Locale::Utils::Tool::walk_hash(
            \%report,
            sub {
                my ( $phrase, $instances ) = @_;
                Cpanel::Locale::Utils::Tool::Find::walk_hash_output( $phrase, $instances, $find_opts );
            },
            ( $opts->{'interactive'} ? 0 : 1 ),
        );
    }

    if ( keys %new_phrases ) {
        if ( $opts->{'interactive'} && Cpanel::Locale::Utils::Tool::is_interactive() ) {
            IO::Prompt::prompt( "[Press enter to continue to list of queued phrases]", "-tty", "-clear" );    # IO::Prompt brought in via Cpanel::Locale::Utils::Tool
        }

        if ( keys %skipped ) {
            print style( "info", "You chose not to queue these phrases:" ) . "\n";
            my $n = 0;
            for my $sp ( sort keys %skipped ) {
                $n++;
                print indent() . "$n. $sp\n";
            }
            print "\n";
        }

        print style( "info", "Queued Phrases:" ) . "\n";
        my $n = 0;
        for my $np ( sort keys %new_phrases ) {
            $n++;
            print indent() . "$n. $np\n";
        }

        if ( $opts->{'dryrun'} ) {
            print "\n";
            print style( "warn", "In dryrun mode, nothing added." ) . "\n";
        }
        else {
            if ( $opts->{'devel'} ) {
                system("git add locale/queue/pending.yaml && git commit -n -e -m 'TEMP QUEUE: queue --devel for development purposes (to be undone for proper harvesting later)'");
            }
        }

    }
    else {
        print "Nothing to queue.\n";
    }
    return;
}

sub _abort_if_repo_has_staged {

    # if they have unstaged changes that is OK, we are only worried abut staged changes since we do not want to accidentally commit them
    system("git diff --exit-code --cached --quiet") && die "Your git repo must have not staged changes while running “queue” under “--devel”.";
    return;
}

1;
