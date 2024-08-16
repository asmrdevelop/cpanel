package Cpanel::SSL::Notify::History::LinkedNodes;

# cpanel - Cpanel/SSL/Notify/History/LinkedNodes.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Notify::History::LinkedNodes

=head1 DESCRIPTION

A datastore for the history of linked-nodes SSL expiry notifications.

=cut

#----------------------------------------------------------------------

use Cpanel::Context                 ();
use Cpanel::Hash                    ();
use Cpanel::Set                     ();
use Cpanel::Transaction::File::JSON ();

our $_PATH;

BEGIN {
    $_PATH = '/var/cpanel/ssl/notify_expiring_certificates_linked_nodes.json';
}

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class. (Loads the datastore.)

=cut

sub new ($class) {
    my $xaction = Cpanel::Transaction::File::JSON->new(
        path => $_PATH,
    );

    $xaction->set_data( {} ) if 'SCALAR' eq ref $xaction->get_data();

    return bless {
        _pid     => $$,
        _xaction => $xaction,
    }, $class;
}

#----------------------------------------------------------------------

=head2 $obj = I<OBJ>->record( $CERT_PEM, $LEVEL )

Stores a single notification, indicated via $LEVEL, for $CERT_PEM.
This won’t actually be saved to disk until C<save()> is called.

=cut

sub record ( $self, $cert_pem, $level ) {
    $self->{'_recorded'}{ _get_cert_hash($cert_pem) } = $level;

    return $self;
}

#----------------------------------------------------------------------

=head2 $obj = I<OBJ>->retain_notifications( $CERT_PEM )

Indicates that $CERT_PEM needed no notifications currently but still
needs its saved notifications retained.

=cut

sub retain_notifications ( $self, $cert_pem ) {
    return $self->record( $cert_pem, undef );
}

#----------------------------------------------------------------------

=head2 @notifications = I<OBJ>->get_sent_notifications( $CERT_PEM )

Returns a list of previously C<record()>ed notifications for $CERT_PEM,
which I<can> be anything but is understood to be an X.509 certificate
in PEM format.

=cut

sub get_sent_notifications ( $self, $cert_pem ) {
    Cpanel::Context::must_be_list();

    my $cert_hash = _get_cert_hash($cert_pem);

    my $history_ar = $self->{'_xaction'}->get_data()->{$cert_hash};

    return $history_ar ? @$history_ar : ();
}

#----------------------------------------------------------------------

=head2 $obj = I<OBJ>->save()

Saves C<record()>ed notifications to disk. Any certificates that were
stored on disk but haven’t gotten a C<record()> during this object’s lifetime
are removed.

=cut

sub save ($self) {
    my $xaction = $self->{'_xaction'};

    my $data_hr = $xaction->get_data();

    my $recorded_hr = $self->{'_recorded'};

    my @to_delete = Cpanel::Set::difference(
        [ keys %$data_hr ],
        [ keys %$recorded_hr ],
    );

    delete @{$data_hr}{@to_delete};

    for my $hash ( keys %$recorded_hr ) {
        if ( $recorded_hr->{$hash} ) {
            push @{ $data_hr->{$hash} }, $recorded_hr->{$hash};
        }
    }

    $xaction->save_and_close_or_die();

    $self->{'_saved'} = 1;

    return;
}

sub DESTROY ($self) {
    if ( !$self->{'_saved'} && $$ == $self->{'_pid'} ) {
        warn "$self is DESTROYed without a save()!";
    }

    return;
}

#----------------------------------------------------------------------

sub _get_cert_hash ($cert_pem) {
    my $pem_nospace = $cert_pem =~ s<\s+><>gr;
    return Cpanel::Hash::fnv1a_32($pem_nospace);
}

1;
