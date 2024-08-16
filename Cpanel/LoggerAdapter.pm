package Cpanel::LoggerAdapter;

# cpanel - Cpanel/LoggerAdapter.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Logger::Persistent ();

our $VERSION = '0.0.4';

sub new {
    my ( $class, $arg_ref ) = @_;

    # SEC-494: We need to instantiate the logger object here. This behavior is relied upon in certain areas.
    return bless { _logger => Cpanel::Logger::Persistent->new($arg_ref) }, $class;
}

sub info {
    return $_[0]->{'_logger'}->info( @_[ 1 .. $#_ ] );
}

sub warn {
    return $_[0]->{'_logger'}->warn( @_[ 1 .. $#_ ] );
}

sub throw {
    my $self = shift;
    eval { $self->{'_logger'}->die(@_); };
    require Cpanel::Carp;
    die Cpanel::Carp::safe_longmess(@_);
}

# Needed for legacy queueprocd and  Cpanel::StateFile compat
sub notify {
    my ( $self, $subj, $msg ) = @_;
    return $self->{'_logger'}->notify( 'notify', { 'subject' => $subj, 'message' => $msg } );
}

1;    # Magic true value required at end of module
__END__

=head1 NAME

Cpanel::LoggerAdapter - Adapt the interface from Cpanel::Logger to that needed for the TaskQueue.

=head1 VERSION

This document describes Cpanel::LoggerAdapter version 0.0.3


=head1 SYNOPSIS

    use Cpanel::LoggerAdapter;

=head1 DESCRIPTION

Simple adapter of the L<Cpanel::Logger> interface to the one needed for L<Cpanel::TaskQueue>.

=head1 INTERFACE

=over

=item info

=item warn

=item throw

=back

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::LoggerAdapter requires no configuration files or environment variables.

=head1 DEPENDENCIES

L<Cpanel::Logger>

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

G. Wade Johnson  C<< wade@cpanel.net >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009, cPanel, Inc. All rights reserved.
