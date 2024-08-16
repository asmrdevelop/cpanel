package Whostmgr::TweakSettings::Configure::Mail;

# cpanel - Whostmgr/TweakSettings/Configure/Mail.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::TweakSettings::Configure::Mail - Interface to C<Mail> tweak
settings.

=head1 SYNOPSIS

    my $mail_hr = Whostmgr::TweakSettings::get_conf('Mail');

    my $globalspamassassin = $mail_hr->{'globalspamassassin'};

=head1 DESCRIPTION

This module is not intended to be called directly and should generally
be called only via L<Whostmgr::TweakSettings>.

B<NOTE:> Currently only the read functions are defined. To implement
writer functionality, follow the pattern of other subclasses of
L<Whostmgr::TweakSettings::Configure::Base>.

=cut

#----------------------------------------------------------------------

use parent 'Whostmgr::TweakSettings::Configure::Base';

use Hash::Merge ();

use Cpanel::Transaction::File::LoadConfig ();
use Whostmgr::Mail::RBL                   ();

# overridden in tests
our $_PATH        = '/etc/exim.conf.localopts';
our $_SHADOW_PATH = '/etc/exim.conf.localopts.shadow';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 I<CLASS>->new()

Instantiates this class.

=cut

sub get_exim_localopts_loadconfig_args {
    return (
        'path'               => $_PATH,
        'delimiter'          => '=',
        'allow_undef_values' => 1,
        regexp_to_preprune   => undef,
        comment              => undef,
        permissions          => 0644,     # users need access
    );
}

sub get_exim_localopts_shadow_loadconfig_args {
    return (
        'path'               => $_SHADOW_PATH,
        'delimiter'          => '=',
        'allow_undef_values' => 1,
        regexp_to_preprune   => undef,
        comment              => undef,
        permissions          => 0600,            # users mustn't access
    );
}

sub new ( $class, %opts ) {

    my $localopts_transaction = Cpanel::Transaction::File::LoadConfig->new( get_exim_localopts_loadconfig_args() );
    my $localopts_data        = $localopts_transaction->get_data();

    # will be empty on reset
    if ( !$localopts_data || ref $localopts_data ne 'HASH' ) {
        $localopts_data = {};
    }

    my $shadow_transaction = Cpanel::Transaction::File::LoadConfig->new( get_exim_localopts_shadow_loadconfig_args() );
    my $shadow_data        = $shadow_transaction->get_data();

    # will be empty on reset
    if ( !$shadow_data || ref $shadow_data ne 'HASH' ) {
        $shadow_data = {};
    }

    my $data = Hash::Merge::merge( $localopts_data, $shadow_data );

    if ( my $rbls_hr = Whostmgr::Mail::RBL::list_rbls_from_yaml() ) {

        # RBLs which do not have a setting are enabled -- we need the ui to reflect this so custom rbls display correctly
        foreach my $rbl ( keys %{$rbls_hr} ) {
            $data->{ 'acl_' . $rbl . '_rbl' } //= 0;    # these are off by default if not defined
        }
    }

    return bless {
        '_data'          => $data,
        '_original_data' => { %{$data} },               # Copy
    }, $class;
}

=head2 $conf_hr = I<OBJ>->get_conf()

Returns the current configuration key value pairs for the module
as a hash reference.

=cut

sub get_conf {
    return $_[0]->{'_data'};
}

=head2 $conf_hr = I<OBJ>->save()

Save the 'Mail' tweak settings.
Only intended to be called from Whostmgr::TweakSettings

=cut

sub save {
    my ($self) = @_;
    my $transaction = Cpanel::Transaction::File::LoadConfig->new( get_exim_localopts_loadconfig_args() );
    $transaction->set_data( $self->{'_data'} );
    my ( $ok, @ret ) = $transaction->save_or_die( 'do_sort' => 1 );
    return $ok;
}

1;
