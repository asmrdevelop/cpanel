package Cpanel::ApacheConf::ModRewrite::DirectiveHasArgs;

# cpanel - Cpanel/ApacheConf/ModRewrite/DirectiveHasArgs.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::ApacheConf::ModRewrite::Directive );

use Cpanel::ApacheConf::ModRewrite::Utils ();
use Cpanel::Context                       ();

#This conflates flags for RewriteRule and RewriteCond. This is safe
#as long as mod_rewrite won’t use the same abbreviation for two
#different directives’ flags.
#NOTE: These are largely untested because we don’t currently need them;
#they’re in here for potential future use.
my %_SHORT_FLAG = (

    #RewriteCond
    nocase => 'NC',    #RewriteRule also has this one
    ornext => 'OR',
    novary => 'NV',

    #NB: Some of these, like “B” and “END”, have no short values.
    backrefnoplus => 'BNP',
    chain         => 'C',
    discardpath   => 'DPI',
    forbidden     => 'F',
    gone          => 'G',
    last          => 'L',
    next          => 'N',
    noescape      => 'NE',
    nosubreq      => 'NS',
    proxy         => 'P',
    passthrough   => 'PT',
    qsappend      => 'QSA',
    qsdiscard     => 'QSD',
    qslast        => 'QSL',

    #The following aren’t really “flags” since they take values,
    #but they’re given in the “flags” section nonetheless.
    cookie   => 'CO',
    env      => 'E',
    Handler  => 'H',
    redirect => 'R',
    skip     => 'S',
    type     => 'T',
);

sub has_flag {
    my ( $self, $flag ) = @_;

    #Ask for them by name!
    die "Invalid flag: “$flag”" if -1 != index( $flag, '=' );

    my @flags = map { s<=.*><>r } @{ $self->{'_flags'} };

    #Normalize everything.
    $_ = $_SHORT_FLAG{$_} || $_ for ( $flag, @flags );

    return scalar grep { $_ eq $flag } @flags;
}

sub new_from_string {
    my ( $class, $line ) = @_;

    my @args = $class->_parse_directive_line($line);

    my $self = { $class->_args_to_self_parts(@args) };

    return bless $self, $class;
}

sub to_string {
    my ($self) = @_;

    my @args = $self->_stringify_args();

    $_ = Cpanel::ApacheConf::ModRewrite::Utils::escape_for_stringify($_) for @args;

    return join( q< >, $self->DIRECTIVE_NAME(), @args );
}

#----------------------------------------------------------------------

#Subclasses must implement these methods!
sub _args_to_self_parts { ... }

#----------------------------------------------------------------------

#only used in tests
sub _get_flags {
    my ($self) = @_;

    die 'list only!' if !wantarray;

    my %_LONG_FLAG = reverse %_SHORT_FLAG;

    my @flags = @{ $self->{'_flags'} };

    s<([^=]+)><$_LONG_FLAG{$1} || $1>e for @flags;

    return sort @flags;    ##no critic qw( ProhibitReturnSort )
}

#----------------------------------------------------------------------

sub _parse_directive_line {
    my ( $class, $line ) = @_;

    Cpanel::Context::must_be_list();

    my $directive = $class->DIRECTIVE_NAME();

    $line =~ m<\A[ \t]*\Q$directive\E[ \t]+(.+)> or do {
        die "“$directive” directive must start with “$directive”! ($line)";
    };

    return Cpanel::ApacheConf::ModRewrite::Utils::parseargline($1);
}

#----------------------------------------------------------------------

1;
