package Cpanel::Locale::Utils::Tool::Lex;

# cpanel - Cpanel/Locale/Utils/Tool/Lex.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Locale::Utils::Tool;    # indent(), style()

sub subcmd {
    my ( $app, $phrase, @args ) = @_;
    die "'lex' only takes one argument: a string to look for\n" if @args;

    die "'lex' requires a string to look for\n" if !defined $phrase || $phrase eq '';
    $phrase = Cpanel::Locale::Utils::Tool::shell_escape_bn($phrase);

    print style( "highlight", "Lexicon:" ) . "\n";
    system( 'git', 'grep', '-i', '-h', $phrase, '/usr/local/cpanel/locale/en.yaml' ) && _none();

    print style( "highlight", "Queue:" ) . "\n";
    system( 'git', 'grep', '-i', '-h', $phrase, '/usr/local/cpanel/locale/queue/pending.yaml' ) && _none();
    return;
}

sub _none {
    print indent() . "no matches\n";
    return;
}

1;
