package Whostmgr::Transfers::Utils::XferPoint::Params;

# cpanel - Whostmgr/Transfers/Utils/XferPoint/Params.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Utils::XferPoint::Params

=head1 SYNOPSIS

XXXX

=head1 DESCRIPTION

XXXX

=cut

#----------------------------------------------------------------------

=head1 ACCESSORS

=over

=item * C<username>

=item * C<sourceip>, C<destip>, C<sharedip>

=item * C<domain>

=item * C<nameservers> (returns list)

=back

=cut

use Class::XSAccessor (
    getters => [
        qw( username sourceip destip domain sharedip ),
    ],
);

my %FLAG = (
    skip_dynamic_block => 1,
);

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( @ARGS )

@ARGS are the args given to the script, which are:

=over

=item * username

=item * source IP address

=item * destination IP address

=item * domain

=item * shared IP address

=item * numeric flags

=item * new email address

=item * … and a list of nameservers

=back

=cut

my @args_order = qw( username sourceip destip domain sharedip flags );

sub new ( $class, @args ) {
    my @nameservers = splice( @args, 0 + @args_order );

    my %self;
    @self{@args_order} = @args;

    if ( $self{'flags'} && $self{'flags'} =~ tr<.><> ) {
        unshift @nameservers, $self{'flags'};
        $self{'flags'} = 0;
    }

    $self{'nameservers'} = \@nameservers;

    return bless \%self, $class;
}

# doc’d as accessor above
sub nameservers ($self) {
    return @{ $self->{'nameservers'} };
}

=head2 $yn = I<OBJ>->skip_dynamic_block()

Returns a boolean that indicates whether the args given to the constructor
indicate to skip the blocking of dynamic content.

=cut

sub skip_dynamic_block ($self) {
    return $self->{'flags'} & $FLAG{'skip_dynamic_block'};
}

1;
