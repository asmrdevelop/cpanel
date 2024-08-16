package Cpanel::FHTrap;

# cpanel - Cpanel/FHTrap.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Parser::Vars ();

#
# trap_defaultfh is a workaround for our earlier design flaws in api1
# it is intended only as a workaround and should not be copied or used elsewhere.
#
sub new {
    my ($class) = @_;

    my $self = { 'result' => '' };

    if ( !$Cpanel::Parser::Vars::trap_defaultfh ) {
        $self->{'need_unset_trap_defaultfh'} = 1;
        $Cpanel::Parser::Vars::trap_defaultfh = 1;
    }

    open( $self->{'fh'}, ">", \$self->{'result'} ) || die "Failed to open scalar reference: $!";

    $self->{'oldfh'} = select( $self->{'fh'} ) || die "Could not select new file handle";    ## no critic qw(Perl::Critic::Policy::InputOutput::ProhibitOneArgSelect)

    return bless $self, $class;
}

sub process {
    my ($self) = @_;

    if ( delete $self->{'need_unset_trap_defaultfh'} ) {
        $Cpanel::Parser::Vars::trap_defaultfh = 0;
    }

    select( delete $self->{'oldfh'} ) || die "Failed to select old file handle";             ## no critic qw(Perl::Critic::Policy::InputOutput::ProhibitOneArgSelect)
    delete $self->{'fh'};

    if ($Cpanel::Parser::Vars::jsonmode) {
        require Cpanel::JSON;
        print Cpanel::JSON::Dump( $self->{'result'} );
    }
    else {
        require Cpanel::Encoder::Tiny;
        print Cpanel::Encoder::Tiny::safe_xml_encode_str( $self->{'result'} );
    }

    return delete $self->{'result'};
}

sub close {
    my ($self) = @_;

    if ( delete $self->{'need_unset_trap_defaultfh'} ) {
        $Cpanel::Parser::Vars::trap_defaultfh = 0;
    }

    select( delete $self->{'oldfh'} ) || die "Failed to select old file handle";    ## no critic qw(Perl::Critic::Policy::InputOutput::ProhibitOneArgSelect)

    delete $self->{'fh'};

    return delete $self->{'result'};
}

sub peek {
    return $_[0]->{'result'};
}

sub DESTROY {
    if ( $_[0]->{'oldfh'} ) {
        select( delete $_[0]->{'oldfh'} );    ## no critic qw(Perl::Critic::Policy::InputOutput::ProhibitOneArgSelect)
    }
    return 1;
}

1;
