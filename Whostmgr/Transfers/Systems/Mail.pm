package Whostmgr::Transfers::Systems::Mail;

# cpanel - Whostmgr/Transfers/Systems/Mail.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# RR Audit: JTK

use Try::Tiny;

use Cpanel::ConfigFiles                  ();
use Cpanel::Email::Aliases               ();
use Cpanel::Email::Perms::System         ();
use Cpanel::Email::Utils                 ();
use Cpanel::FileUtils::Write             ();
use Cpanel::LoadFile::ReadFast           ();
use Cpanel::Email::Constants             ();
use Cpanel::Locale                       ();
use Cpanel::PwCache                      ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::SafeRun::Simple              ();

use constant _ENOENT => 2;

use parent qw(
  Whostmgr::Transfers::SystemsBase::Distributable::Mail
);

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This resets email quotas to safe values and restores email aliases, filters and mail items.') ];
}

sub get_restricted_available {
    return 1;
}

sub _do_nothing { return }

sub unrestricted_restore {
    my ($self) = @_;

    my $extractdir = $self->extractdir();

    my $newuser_uid = ( Cpanel::PwCache::getpwnam( $self->newuser ) )[2];

    my @domains = $self->{'_utils'}->domains();

    $self->start_action('Restoring Mail files');

    my @valiases_domains_to_update;

    foreach my $gdomain (@domains) {

        my $valiases_archive       = "$extractdir/va/$gdomain";
        my $vdomainaliases_archive = "$extractdir/vad/$gdomain";
        my $vfilters_archive       = "$extractdir/vf/$gdomain";

        if ( open my $va_archive_fh, '<', $valiases_archive ) {
            my $valiases_dest = "$Cpanel::ConfigFiles::VALIASES_DIR/$gdomain";
            local $Cpanel::CONF{'VALIASDIR'} = $Cpanel::ConfigFiles::VALIASES_DIR;

            my ( $ok, $err ) = $self->_write_mail_file( $valiases_dest => $va_archive_fh );
            $self->warn($err) if !$ok;

            push @valiases_domains_to_update, $gdomain;
        }
        elsif ( $! != _ENOENT() ) {
            $self->warn("open($valiases_archive): $!");
        }

        my %copy_to = (
            $vdomainaliases_archive => "$Cpanel::ConfigFiles::VDOMAINALIASES_DIR/$gdomain",
            $vfilters_archive       => "$Cpanel::ConfigFiles::VFILTERS_DIR/$gdomain",
        );

        for my $source ( keys %copy_to ) {
            my $dest = $copy_to{$source};

            if ( open my $rfh, '<', $source ) {
                my ( $ok, $err ) = $self->_write_mail_file( $dest, $rfh );
                $self->warn($err) if !$ok;
            }
            elsif ( $! != _ENOENT() ) {
                $self->warn("open($valiases_archive): $!");
            }
        }

        Cpanel::Email::Perms::System::ensure_domain_system_perms( $newuser_uid, $gdomain );
    }

    if (@valiases_domains_to_update) {
        my $privs_ar = Cpanel::AccessIds::ReducedPrivileges->new( $self->newuser() );

        for my $gdomain (@valiases_domains_to_update) {
            my $aliases_obj;
            try {
                $aliases_obj = Cpanel::Email::Aliases->new(
                    domain => $gdomain,
                );
            }
            catch {
                $self->warn($_);
            };

            if ($aliases_obj) {
                $self->_update_valiases_config($aliases_obj);
                try {
                    $aliases_obj->save();
                }
                catch {
                    $self->warn($_);
                };
            }
        }
    }

    $self->start_action('Resetting Quotas to sane values');
    $self->out( Cpanel::SafeRun::Simple::saferun( $Cpanel::ConfigFiles::CPANEL_ROOT . '/scripts/reset_mail_quotas_to_sane_values', '--force', '--confirm', $self->newuser() ) );

    return 1;
}

*restricted_restore = \&unrestricted_restore;

sub _write_mail_file {
    my ( $self, $path, $contents_fh ) = @_;

    my $newuser = $self->newuser();
    my $data    = '';
    Cpanel::LoadFile::ReadFast::read_all_fast( $contents_fh, $data );
    Cpanel::FileUtils::Write::overwrite_no_exceptions( $path, $data, Cpanel::Email::Constants::VFILE_PERMS() ) or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to write the file “[_1]” because of an error: [_2]', $path, $! ) );
    };

    return 1;
}

sub _update_valiases_config {
    my ( $self, $aliases_obj ) = @_;

    my $newuser = $self->newuser();
    my $olduser = $self->olduser();

    for my $alias ( $aliases_obj->get_aliases() ) {
        for my $dest ( $aliases_obj->get_destinations($alias) ) {
            if ( $dest eq $olduser ) {
                $aliases_obj->remove( $alias, $dest );
                $aliases_obj->add( $alias, $newuser );
            }
            elsif ( $self->_looks_like_auto_responder($dest) ) {
                $aliases_obj->remove( $alias, $dest );
                $aliases_obj->add( $alias, $self->_get_new_autoresponder_valiases_line($alias) );
            }
        }
    }

    my $default_dest = $aliases_obj->get_default_destination();
    if ($default_dest) {
        $aliases_obj->set_default_destination( $self->_get_updated_wildcard_forwarder_line($default_dest) );
    }

    return;
}

sub _looks_like_auto_responder {
    my ( $self, $dest ) = @_;

    return ( $dest =~ /autorespond/ && $dest =~ m{/usr/local/cpanel} ) ? 1 : 0;
}

sub _get_new_autoresponder_valiases_line {
    my ( $self, $address ) = @_;

    my $user_homedir = $self->homedir();

    return "\"|/usr/local/cpanel/bin/autorespond $address $user_homedir/.autorespond\"";
}

sub _get_updated_wildcard_forwarder_line {
    my ( $self, $wildcard_forwarder_line ) = @_;

    my $olduser = $self->{'_utils'}->original_username();
    my $newuser = $self->{'_utils'}->local_username();

    my @forwarders = Cpanel::Email::Utils::get_forwarders_from_string($wildcard_forwarder_line);

    return join( ",", map { $_ eq $olduser ? $newuser : $_ } @forwarders );
}

1;
