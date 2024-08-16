package Cpanel::Locale::Utils::Tool::Dequeue;

# cpanel - Cpanel/Locale/Utils/Tool/Dequeue.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Locale::Utils::Tool;    # indent(), style()
use Cpanel::Locale::Utils::Queue ();
use Cpanel::Locale::Utils::Paths ();
use Cpanel::DataStore            ();

sub subcmd {
    my ( $app, $phrase, @args ) = @_;
    die "'dequeue' only takes one argument: the phrase you want to remove\n" if @args;

    die "'dequeue' requires the phrase you want to remove\n" if !defined $phrase || $phrase eq '';
    print "Remove from queue: $phrase\n";

    if ( phrase_is_in_lexicon($phrase) ) {

        print "The phrase is no longer in the queued state.\n";
        return;
    }

    my $file_count    = 0;
    my $remove_cnt    = 0;
    my $pending_queue = Cpanel::Locale::Utils::Queue::get_pending_file();
    for my $yaml (
        $pending_queue,
        glob( Cpanel::Locale::Utils::Paths::get_locale_yaml_root() . '/*.yaml' ),
    ) {

        Cpanel::DataStore::edit_datastore(
            $yaml,
            sub {
                my ($hr) = @_;
                $file_count++;

                return if !exists $hr->{$phrase};

                if ( $yaml eq $pending_queue ) {
                    print indent() . "Removing from main pending queue …\n";
                }
                else {
                    if ( $yaml =~ m{/([^/]+)/([^/]+)\.yaml$} ) {
                        my ( $type, $tag ) = ( $1, $2 );
                        print indent() . "Removing from “$type” queue for “$tag” …\n";
                    }
                    else {
                        print indent() . "Removing from file “$yaml” …\n";    # how did we get here?
                    }
                }

                delete $hr->{$phrase};
                $remove_cnt++;
                return 1;    # true means to save the new ref to disk
            }
        );
    }

    print style( "info", "Files checked:" ) . " $file_count\n";
    print style( "info", "Removed from :" ) . " $remove_cnt\n";

    return;
}

sub phrase_is_in_lexicon {
    my ($phrase) = @_;

    my $lexicon_hr = Cpanel::DataStore::fetch_ref( Cpanel::Locale::Utils::Paths::get_locale_yaml_root() . '/en.yaml' );

    return 1 if exists $lexicon_hr->{$phrase};
    return;
}

1;
