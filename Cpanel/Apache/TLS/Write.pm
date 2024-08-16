package Cpanel::Apache::TLS::Write;

# cpanel - Cpanel/Apache/TLS/Write.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::LoadModule ();

=encoding utf-8

=head1 NAME

Cpanel::Apache::TLS::Write - writer for Apache’s SSL/TLS certificate datastore

=head1 SYNOPSIS

    $atls_wr = Cpanel::Apache::TLS::Write->new();

See L<Cpanel::Domain::TLS::Write> for methods you can call with this object.

=head1 DESCRIPTION

This module writes to Apache TLS. Because writes to this datastore are meant
to be kept in sync with Apache TLS’s index database
(cf. L<Cpanel::Apache::TLS::Index>), this module (unlike
L<Cpanel::Apache::TLS>) needs to be instantiated prior to use.

You can also use the read methods from L<Cpanel::Apache::TLS> on this object,
though there probably isn’t any good reason to.

=cut

use parent qw(
  Cpanel::Apache::TLS
  Cpanel::Domain::TLS::Write
);

use constant {

    #override parent class
    _unset_task => 'unset_apache_tls',
};

#An empty list to override behavior in Domain TLS.
use constant _ensure_certificate_object_matches_entry => ();

#So the combined files aren’t readable by “mail” as Domain TLS does it.
use constant _COMBINED_OWNER_IDS => ();

#This is a no-op because Apache TLS already locks SQLite and so doesn’t
#need the underlying Domain TLS lock as well.
sub __get_write_lock { }

=head1 METHODS

=head2 I<CLASS>->new()

Returns an instance of this class, which you can use to update the
database.

=cut

sub new {
    my ($class) = @_;

    $class->init();

    return bless {}, $class;
}

sub _idx {
    my ($self) = @_;

    #We lazy-load here so that we can run inherited methods without having
    #loaded the Index module, which brings in DBD::SQLite and so is heavy.
    return $self->{'_idx'} ||= do {
        Cpanel::LoadModule::load_perl_module('Cpanel::Apache::TLS::Index');
        Cpanel::Apache::TLS::Index->new();
    };
}

#----------------------------------------------------------------------
# Design note:
#
# This module is a bit tightly coupled to Domain TLS—which is to say that
# there are bits in Domain TLS that are slightly “aware” of Apache TLS.
# It’s a bit less than ideal; that said, it seems unlikely that we’ll make
# further use of Domain TLS as a base class anytime soon.
#----------------------------------------------------------------------

=head2 $count = I<OBJ>->enqueue_unset_tls( VHOST_NAME1, VHOST_NAME2, .. )

Similar to L<Cpanel::Domain::TLS::Write>’s equivalent function.
As with that function, this is the
generally-preferred way to remove entries from this datastore. Errors are
handled the same way as well.

=cut

sub enqueue_unset_tls {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $self     = shift;
    my $names_ar = \@_;

    #Implementation note: each individual entry gets a separate transaction
    #in the index database because this is how we ensure consistency between
    #the filesystem and the index DB. The batching allows us not to schedule
    #the cleanup task a zillion times, e.g., when removing an account that
    #has thousands of domains.
    my $count = $self->_unset_idx_and_super( '__enqueue_unset_tls_no_task_queue', $names_ar );

    $self->__schedule_cleanup_task() if $count;

    return $count;
}

=head2 $count = I<OBJ>->unset_tls( VHOST_NAME )

Similar to C<enqueue_unset_tls()> but works immediately. The same
caveats apply as in L<Cpanel::Domain::TLS::Write>’s equivalent function;
i.e., for most cases you should use C<enqueue_unset_tls()> instead.

=cut

sub unset_tls {
    my ( $self, $vhost ) = @_;

    return $self->_unset_idx_and_super( 'unset_tls', $vhost );
}

sub _unset_idx_and_super {
    my ( $self, $super_func, $vhost_data ) = @_;

    my $vhosts = ref $vhost_data ? $vhost_data : [$vhost_data];

    my $savept = join( '_', $super_func, $vhosts->[0], $$ );

    my $xaction = $self->_idx()->start_transaction($savept);

    foreach my $vhost (@$vhosts) {
        $self->_idx()->unset($vhost);
    }

    substr( $super_func, 0, 0 ) = 'SUPER::';

    my $ret = $self->$super_func($vhost_data);

    $xaction->release();

    return $ret;
}

=head2 $count = I<OBJ>->rename( OLD_VHOST_NAME => NEW_VHOST_NAME )

Renames an entry’s C<virtual_host> if it exists. Returns 1 if an
entry was updated, or 0 if nothing actually happened (because
OLD_VHOST_NAME doesn’t actually match any DB records).

=cut

sub rename {
    my ( $self, $old, $new ) = @_;

    my $savept = "rename_${old}_${new}_$$";

    my $xaction = $self->_idx()->start_transaction($savept);

    my $exists = $self->_idx()->rename( $old, $new );

    if ($exists) {
        $self->SUPER::rename( $old, $new );
    }

    $xaction->release();

    return $exists ? 1 : 0;
}

#----------------------------------------------------------------------

sub _set_tls__no_verify__crt_obj {
    my ( $self, %opts ) = @_;

    my $savept = "set_$opts{'vhost_name'}_$$";

    my $xaction = $self->_idx()->start_transaction($savept);

    $self->_idx()->set( $opts{'vhost_name'}, $opts{'certificate'} );

    $opts{'domain'} = delete $opts{'vhost_name'};

    $self->SUPER::_set_tls__no_verify__crt_obj(%opts);

    $xaction->release();

    return;
}

1;
