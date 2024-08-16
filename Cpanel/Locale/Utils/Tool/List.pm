package Cpanel::Locale::Utils::Tool::List;

# cpanel - Cpanel/Locale/Utils/Tool/List.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Locale::Utils::Tool::Find ();

sub subcmd {
    my ( $app, $resource, @args ) = @_;

    if ( $resource eq '-' ) {
        print "Processing files provided via STDIN …\n";
        $resource = [<STDIN>];
        chomp( @{$resource} );
    }
    my %flags;
    @flags{qw( all passed warnings violations parse-tpds verbose extra-filters no-git-check )} = ();
    for my $flag (@args) {
        my $dashless = $flag;
        $dashless =~ s/^--//;
        die "'list' does not know about '$flag'" if !exists $flags{$dashless};
    }

    my $opts = {};
    for my $bool ( keys %flags ) {
        $opts->{$bool} = grep( /^--$bool$/, @args ) ? 1 : 0;
    }

    # If none of the passed, warnings, and violations options specified, then do all of them.
    if ( $opts->{'all'} || !( $opts->{'passed'} || $opts->{'warnings'} || $opts->{'violations'} ) ) {
        $opts->{'passed'}     = 1;
        $opts->{'warnings'}   = 1;
        $opts->{'violations'} = 1;
    }

    $opts->{'return_hash'} = 1;
    my %phrases = Cpanel::Locale::Utils::Tool::Find::run( $resource, $opts );
    my $count   = 0;
    for my $phrase ( sort keys %phrases ) {
        $count++;
        print "$count: $phrase\n";
    }

    return;
}

sub get_help_text {
    return <<'END_HELP';
List phrases found in a given resource.

Options:
  --all            Include known phrases in addition to unknown phrases
  --verbose        Include additional information
  --extra-filters  Enable the phrase checker’s extra filters

                   To find out more about cPanel’s phrase checker filters,
                   see the POD for Cpanel::CPAN::Locale::Maketext::Utils::Phrase::cPanel.

  --no-git-check   If the given resource is a directory include all files in
                   the iteration even if they are outside of the repository.

  --parse-tpds     Instead of executing the Translatable Phrase Dumper Scripts
                   and parsing their output, parse their source code instead.

  By default the following flags are all in effect unless one or more are passed in:

  --passed      Show phrases that passed the phrase checker with no warnings
  --warnings    Show phrases that passed the phrase checker with warnings
  --violations  Show phrases that failed the phrase checker

END_HELP
}

1;
