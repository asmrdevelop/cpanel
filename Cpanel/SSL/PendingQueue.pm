package Cpanel::SSL::PendingQueue;

# cpanel - Cpanel/SSL/PendingQueue.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::SSL::PendingQueue - Manage the cPStore ssl pending order queue.

=cut

use Cpanel::Autodie                       ();
use Cpanel::Context                       ();
use Cpanel::Exception                     ();
use Cpanel::Mkdir                         ();
use Cpanel::OrDie                         ();
use Cpanel::PwCache                       ();
use Cpanel::SSL::PendingQueue::Item       ();
use Cpanel::SSL::Utils                    ();
use Cpanel::Transaction::File::JSON       ();
use Cpanel::Transaction::File::JSONReader ();

my $PENDING_QUEUE_RELATIVE_PATH = '.cpanel/ssl';
my $PENDING_QUEUE_FILE          = "$PENDING_QUEUE_RELATIVE_PATH/pending_queue.json";

my $ITEM_CLASS = 'Cpanel::SSL::PendingQueue::Item';

#STATIC or dynamic
sub read {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    my $xaction = ref($self) && ( ref $self )->isa(__PACKAGE__);
    if ($xaction) {
        $xaction = $self->{'_xaction'};
    }
    else {
        my $pending_queue_file_path = _get_path();

        if ( Cpanel::Autodie::exists($pending_queue_file_path) ) {
            $xaction = Cpanel::Transaction::File::JSONReader->new( path => $pending_queue_file_path );
        }
    }

    my @items;

    if ($xaction) {
        my $data_hr = $xaction->get_data();
        if ( $data_hr && 'SCALAR' ne ref $data_hr ) {
            for my $p ( keys %$data_hr ) {
                for my $oiid ( keys %{ $data_hr->{$p} } ) {
                    my %item = (
                        provider      => $p,
                        order_item_id => $oiid,
                        %{ $data_hr->{$p}{$oiid} },

                        # We want to ensure that csr_parse is always
                        # an object, which will happen if we withhold
                        # any cached parse.
                        csr_parse => undef,
                    );

                    push @items, $ITEM_CLASS->new( \%item );
                }
            }
        }
    }

    return @items;
}

#----------------------------------------------------------------------

sub new {
    my ($class) = @_;

    my $home_dir = Cpanel::PwCache::gethomedir();

    my $pending_queue_file_path = _get_path();

    Cpanel::Mkdir::ensure_directory_existence_and_mode( "$home_dir/$PENDING_QUEUE_RELATIVE_PATH", 0700 );

    my $xaction = Cpanel::Transaction::File::JSON->new( path => $pending_queue_file_path );

    #Initialize a new datastore.
    if ( 'SCALAR' eq ref $xaction->get_data() ) {
        $xaction->set_data( {} );
    }

    return bless { _xaction => $xaction }, $class;
}

sub finish {
    my ($self) = @_;
    $self->{'_xaction'}->save_and_close_or_die();
    return 1;
}

sub close {
    my ($self) = @_;
    $self->{'_xaction'}->close_or_die();
    return 1;
}

# Requires the same args (in a literal list) as the hashref
# that Item->new() requires.
#
sub add_item {
    my ( $self, %attrs ) = @_;

    my $data_hr = $self->{'_xaction'}->get_data();

    #Validate the data
    Cpanel::SSL::PendingQueue::Item->new( {%attrs} );

    #This ensures that the “csr” value is a real CSR.
    Cpanel::OrDie::multi_return(
        sub {
            Cpanel::SSL::Utils::parse_csr_text( $attrs{'csr'} );
        },
    );

    #We could validate the product_id here, and/or validate that the CSR covers
    #domains that the user actually controls, but probably all that would
    #accomplish is making this module harder to test.

    my ( $provider, $order_item_id ) = delete @attrs{qw(provider order_item_id)};

    if ( exists $data_hr->{$provider}{$order_item_id} ) {
        die Cpanel::Exception::create( 'EntryAlreadyExists', 'An entry with the order item [asis,ID] “[_1]” for the provider “[_2]” already exists.', [ $order_item_id, $provider ] );
    }

    $attrs{'created_time'} ||= time;

    $data_hr->{$provider}{$order_item_id} = \%attrs;

    return;
}

#This will be called after payment: now we can start checking
#for the delivered cert.
sub set_certificate_to_confirmed {
    my ( $self, %attrs ) = @_;

    my ( $p, $oiid ) = $self->_get_provider_and_order_item_id(%attrs);

    my $data_hr = $self->{'_xaction'}->get_data();
    $data_hr->{$p}{$oiid}{'status'} = 'confirmed';

    return;
}

sub _get_provider_and_order_item_id {
    my ( $self, %attrs ) = @_;

    my @missing_required_parms = grep { !length $attrs{$_} } qw( provider order_item_id );
    if (@missing_required_parms) {
        die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing_required_parms ] );
    }

    my ( $provider, $order_item_id ) = @attrs{qw(provider order_item_id)};

    my $data_hr = $self->{'_xaction'}->get_data();
    $self->_validate_order_exists( $data_hr, $provider, $order_item_id );

    return ( $provider, $order_item_id );
}

sub _validate_order_exists {
    my ( $self, $data_hr, $provider, $order_item_id ) = @_;

    $data_hr->{$provider} && $data_hr->{$provider}{$order_item_id} or do {
        _die_no_entries( $provider, $order_item_id );
    };

    return;
}

sub _die_no_entries {
    my ( $provider, $order_item_id ) = @_;
    die Cpanel::Exception::create( 'EntryDoesNotExist', 'No entry exists for provider “[_1]” and order item [asis,ID] “[_2]”.', [ $provider, $order_item_id ] );
}

sub _die_if_not_item_obj {
    my ($item_obj) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'item_obj' ] ) if !defined $item_obj;

    die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” should be an object of the class “[_2]”.', [ 'item_obj', $ITEM_CLASS ] ) if !try { $item_obj->isa($ITEM_CLASS) };

    return 1;
}

=head2 get_item_by_provider_order_item_id($provider, $order_item_id)

Returns a Cpanel::SSL::PendingQueue::Item object
for the provided $provider and $order_item_id

This function throws an exeception if there is
not matching item in the queue.

=cut

sub get_item_by_provider_order_item_id {
    my ( $self, $provider, $order_item_id ) = @_;
    my $data_hr = $self->{'_xaction'}->get_data();
    $self->_validate_order_exists( $data_hr, $provider, $order_item_id );
    return $ITEM_CLASS->new(
        {
            provider      => $provider,
            order_item_id => $order_item_id,
            %{ $data_hr->{$provider}{$order_item_id} },
        },
    );
}

sub update_item {
    my ( $self, $item_obj ) = @_;

    _die_if_not_item_obj($item_obj);

    my $data_hr = $self->{'_xaction'}->get_data();

    my ( $provider, $order_item_id ) = map { $item_obj->$_() } qw(provider order_item_id);

    $self->_validate_order_exists( $data_hr, $provider, $order_item_id );

    my @properties_to_copy = qw(
      first_poll_time
      last_poll_time
      status
      last_status_code
      last_action_urls
    );

    @{ $data_hr->{$provider}{$order_item_id} }{@properties_to_copy} = map { $item_obj->$_() } @properties_to_copy;

    return;
}

sub remove_item {
    my ( $self, $item_obj ) = @_;

    _die_if_not_item_obj($item_obj);

    my ( $provider, $order_item_id ) = map { $item_obj->$_() } qw(provider order_item_id);
    my $data_hr = $self->{'_xaction'}->get_data();

    $self->_validate_order_exists( $data_hr, $provider, $order_item_id );

    #Might as well do this here.
    require Cpanel::Market::SSL::DCV::User;
    Cpanel::Market::SSL::DCV::User::undo_dcv_preparation(
        provider      => $provider,
        provider_args => {
            product_id => $item_obj->product_id(),
            csr        => $item_obj->csr(),
        },
        domain_dcv_method => $item_obj->domain_dcv_method(),
    );

    delete $data_hr->{$provider}{$order_item_id};

    delete $data_hr->{$provider} if !%{ $data_hr->{$provider} };

    return;
}

sub _get_path {
    my $home_dir = Cpanel::PwCache::gethomedir();

    return "$home_dir/$PENDING_QUEUE_FILE";
}

1;
