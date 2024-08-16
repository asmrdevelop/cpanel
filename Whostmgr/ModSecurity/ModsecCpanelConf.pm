
# cpanel - Whostmgr/ModSecurity/ModsecCpanelConf.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::ModsecCpanelConf;

use strict;
use warnings;

use Cpanel::Autodie  ();
use Cpanel::LoadFile ();
use Cpanel::Locale::Lazy 'lh';
use Cpanel::Logger                        ();
use Cpanel::Sort::Utils                   ();
use Whostmgr::ModSecurity                 ();
use Whostmgr::ModSecurity::Settings       ();
use Whostmgr::ModSecurity::TransactionLog ();
use Cpanel::SysPkgs                       ();
use Whostmgr::ModSecurity::Vendor         ();

# instance serves no purpose other than to store (optional) flags
sub new {
    my ( $package, @args ) = @_;
    my $self = {@args};
    return bless( $self, $package );
}

sub active_configs {
    my ($self) = @_;
    return $self->inspect(
        sub {
            my $data = shift;
            return $data->{active_configs};
        }
    );
}

sub active_vendors {
    my ($self) = @_;
    return $self->inspect(
        sub {
            my $data = shift;
            return $data->{active_vendors};
        }
    );
}

sub disabled_rules {
    my ($self) = @_;
    return $self->inspect(
        sub {
            my $data = shift;
            return $data->{disabled_rules};
        }
    );
}

sub include {
    my ( $self, $config ) = @_;

    # Ignore the return value; just want to make sure the name is valid before we try anything
    Whostmgr::ModSecurity::get_safe_config_filename($config);

    my @result = $self->manipulate(
        sub {
            my $data = shift;
            if ( $data->{active_configs}{$config} ) {
                die lh()->maketext( q{The following configuration is already active: [_1]}, $config ) . "\n";
            }
            $data->{active_configs}{$config} = 1;
        }
    );
    Whostmgr::ModSecurity::TransactionLog::log( operation => 'make_config_active', arguments => { config => $config } );
    return @result;
}

sub uninclude {
    my ( $self, $config ) = @_;

    # Ignore the return value; just want to make sure the name is valid before we try anything
    Whostmgr::ModSecurity::get_safe_config_filename($config);

    my @result = $self->manipulate(
        sub {
            my $data = shift;
            if ( !$data->{active_configs}{$config} ) {
                die lh()->maketext( q{The following configuration is not active: [_1]}, $config ) . "\n";
            }
            delete $data->{active_configs}{$config};
        }
    );
    Whostmgr::ModSecurity::TransactionLog::log( operation => 'make_config_inactive', arguments => { config => $config } );
    return @result;
}

sub enable_vendor {
    my ( $self, $vendor_id ) = @_;
    my @result = $self->manipulate(
        sub {
            my $data = shift;
            $data->{active_vendors}{$vendor_id} = 1;
        }
    );

    Whostmgr::ModSecurity::TransactionLog::log( operation => 'enable_vendor', arguments => { vendor_id => $vendor_id } );
    return @result;
}

sub disable_vendor {
    my ( $self, $vendor_id ) = @_;
    my @result = $self->manipulate(
        sub {
            my $data = shift;
            delete $data->{active_vendors}{$vendor_id};
        }
    );

    Whostmgr::ModSecurity::TransactionLog::log( operation => 'disable_vendor', arguments => { vendor_id => $vendor_id } );
    return @result;
}

sub is_vendor_enabled {
    my ( $self, $vendor_id ) = @_;
    return $self->inspect(
        sub {
            my $data = shift;
            return $data->{active_vendors}{$vendor_id};
        }
    );
}

sub enable_vendor_updates {
    my ( $self, $vendor_id ) = @_;
    my @result = $self->manipulate(
        sub {
            my $data = shift;
            $data->{vendor_updates}{$vendor_id} = 1;
        }
    );

    my $vendor = Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id );
    if ( my $pkg = $vendor->is_pkg ) {
        Cpanel::SysPkgs->new->drop_exclude_rule_for_package($pkg);
    }

    Whostmgr::ModSecurity::TransactionLog::log( operation => 'enable_vendor_updates', arguments => { vendor_id => $vendor_id } );
    return @result;
}

sub disable_vendor_updates {
    my ( $self, $vendor_id ) = @_;
    my @result = $self->manipulate(
        sub {
            my $data = shift;
            delete $data->{vendor_updates}{$vendor_id};
        }
    );

    my $vendor = Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id );

    if ( my $pkg = $vendor->is_pkg ) {
        Cpanel::SysPkgs->new->add_exclude_rule_for_package($pkg);
    }

    Whostmgr::ModSecurity::TransactionLog::log( operation => 'disable_vendor_updates', arguments => { vendor_id => $vendor_id } );
    return @result;
}

sub vendor_updates {
    my ($self) = @_;
    return $self->inspect(
        sub {
            my $data = shift;
            return $data->{vendor_updates} || {};
        }
    );
}

sub add_srrbi {
    my ( $self, $rule_id, $vendor_id ) = @_;
    return $self->manipulate(
        sub {
            my $data = shift;

            # If a vendor id was specified, add that vendor id as the value.
            # Otherwise, just add some true value.
            $data->{disabled_rules}{$rule_id} = $vendor_id || 1;
        }
    );    # No need for Whostmgr::ModSecurity::TransactionLog::log() on add_srrbi because this is already covered by Whostmgr::ModSecurity::Configure
}

sub remove_srrbi {
    my ( $self, $rule_id ) = @_;
    return $self->manipulate(
        sub {
            my $data = shift;
            delete $data->{disabled_rules}{$rule_id};
        }
    );    # No need for Whostmgr::ModSecurity::TransactionLog::log() on remove_srrbi because this is already covered by Whostmgr::ModSecurity::Configure
}

sub remove_all_srrbi_for_vendor {
    my ( $self, $vendor_id ) = @_;
    return $self->remove_srrbi_for_vendor( $vendor_id, sub { 1 } );
}

sub remove_srrbi_for_vendor {
    my ( $self, $vendor_id, $should_remove ) = @_;
    die lh()->maketext(q{The system experienced an internal error in the attempt to re-enable the vendor’s rules. The system could not find the required attributes. File a bug report with cPanel Support.}) . "\n" if !$vendor_id || !$should_remove;
    return $self->manipulate(
        sub {
            my $data = shift;
            for my $rule_id ( keys %{ $data->{disabled_rules} } ) {
                if ( $vendor_id eq $data->{disabled_rules}{$rule_id} ) {
                    if ( $should_remove->($rule_id) ) {
                        delete $data->{disabled_rules}{$rule_id};
                    }
                }
            }
        }
    );
}

sub inspect {
    my ( $self, $inspector ) = @_;

    require Cpanel::CachedDataStore;

    # backup_restore() bypasses CachedDataStore, so we can't use the memory cache
    my $datastore = Cpanel::CachedDataStore::loaddatastore( Whostmgr::ModSecurity::abs_modsec_cpanel_conf_datastore(), 0, undef, { enable_memory_cache => 0 } );

    $datastore->{data}{active_configs} ||= {};
    $datastore->{data}{disabled_rules} ||= {};

    return $inspector->( $datastore->{data} );
}

sub manipulate {
    my ( $self, $changer ) = @_;

    require Cpanel::CachedDataStore;
    my $datastore = Cpanel::CachedDataStore::loaddatastore( Whostmgr::ModSecurity::abs_modsec_cpanel_conf_datastore(), 1, undef, { enable_memory_cache => 0 } );

    my $orig_umask = umask 0077;

    require Cpanel::Hooks;

    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => 'ModSecurity::ModsecCpanelConf::manipulate',
            'stage'    => 'pre',
        },
    );

    eval {
        $datastore->{data}{active_configs} ||= {};
        $datastore->{data}{disabled_rules} ||= {};

        $changer->( $datastore->{data} );

        _build_modsec_cpanel_conf( $self, $datastore->{data} );
        Whostmgr::ModSecurity::validate_httpd_config();

        unless ( $self->{skip_restart} ) {
            require Cpanel::HttpUtils::ApRestart::BgSafe;
            Cpanel::HttpUtils::ApRestart::BgSafe::restart();
        }
    };
    my $exception = $@;

    umask $orig_umask;

    if ($exception) {
        $datastore->abort();
        _restore_orig_modsec_cpanel_conf();
        die $exception;
    }

    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => 'ModSecurity::ModsecCpanelConf::manipulate',
            'stage'    => 'post',
        },
    );

    $datastore->save();
    return 1;
}

sub _build_modsec_cpanel_conf {
    my ( $self, $data ) = @_;

    my ( @manageable_directives, @includes, @disabled_rules );

    for my $directive ( sort keys %{ $data->{settings} } ) {
        my $value = $data->{settings}{$directive};
        push @manageable_directives, [ $directive, $data->{settings}{$directive} ];
    }

    my @all_configs = Cpanel::Sort::Utils::sort_dirdepth_list( keys %{ $data->{active_configs} } );
    for my $config (

        # Ensure that shallower config files are included before deeper config files.
        # This is a rule being applied specifically to target the "setup" file at the
        # top-level of a vendor set, on which other config files depend.
        @all_configs
    ) {
        my $vendor_id = Whostmgr::ModSecurity::extract_vendor_id_from_config_name($config);
        my $filename  = Whostmgr::ModSecurity::get_safe_config_filename($config);

        # Even if this config is active, it still needs to be skipped if it belongs to an inactive vendor set.
        if ( $vendor_id && !$data->{active_vendors}{$vendor_id} ) {
            next;
        }
        push @includes, $filename;
    }

    for my $rule_id ( sort keys %{ $data->{disabled_rules} } ) {
        push @disabled_rules, $rule_id;
    }

    require Cpanel::Template;
    my ( $status, $output_ref ) = Cpanel::Template::process_template(
        'whostmgr',
        {
            template_file => Whostmgr::ModSecurity::abs_modsec_cpanel_conf_template(),
            print         => 0,
            data          => {
                fixed_directives      => Whostmgr::ModSecurity::fixed_directives_ar(),
                manageable_directives => \@manageable_directives,
                includes              => \@includes,
                disabled_rules        => \@disabled_rules,
            }
        }
    );

    rename _abs_mcc(), _abs_mcc() . '.PREVIOUS';

    require Cpanel::FileUtils::Write;
    if ( exists $self->{'output_file'} ) {
        return Cpanel::FileUtils::Write::overwrite_no_exceptions( $self->{'output_file'}, $$output_ref, 0600 );
    }
    return Cpanel::FileUtils::Write::overwrite_no_exceptions( _abs_mcc(), $$output_ref, 0600 );
}

sub setup {
    my ($self) = @_;
    my $logger = Cpanel::Logger->new();

    if ( !Whostmgr::ModSecurity::has_modsecurity_installed() ) {
        $logger->info( lh()->maketext(q{You have not installed [asis,ModSecurity]. No additional setup is required.}) );
        return;
    }

    if ( !-e Whostmgr::ModSecurity::abs_modsec_cpanel_conf_datastore() ) {
        if ( -e _abs_mcc() && !-z _abs_mcc() ) {
            $self->import_from_existing();
            $logger->info( lh()->maketext(q{You have successfully imported the [asis,ModSecurity] configuration from the [asis,pre-datastore] [asis,modsec2.cpanel.conf] file.}) );
        }
        else {
            $self->setup_defaults();
            $logger->info( lh()->maketext(q{You have successfully created the [asis,modsec2.cpanel.conf] file with default configuration settings.}) );
        }
    }
    else {
        $logger->info( lh()->maketext(q{The [asis,modsec2.cpanel.conf] file and its [asis,datastore] are already set up. No further action is required.}) );
    }

    ensure_secdatadir();

    return 1;
}

sub import_from_existing {
    my ($self) = @_;
    Cpanel::Autodie::rename( _abs_mcc(), _abs_mcc() . '.PREVIOUS' );
    eval {
        my $existing_contents = Cpanel::LoadFile::loadfile( _abs_mcc() . '.PREVIOUS' );
        my ( %active_configs, %disabled_rules, %settings );
        for my $line ( split /\n/, $existing_contents ) {
            my $v;
            if ( ($v) = $line =~ m{^\s*Include ["']+([^"']+)} ) {
                my $config = Whostmgr::ModSecurity::to_relative($v);
                $active_configs{$config} = 1;
            }
            elsif ( ($v) = $line =~ m{^\s*SecRuleRemoveById ["']?(\d+)} ) {
                $disabled_rules{$v} = 1;
            }
            elsif ( my ( $directive, $v1, $v2, $v3 ) = $line =~ m{^\s*(Sec\w+)\s+(?:"(.+?)"|'(.+?)'|(.+))\s*$} ) {
                my $v = defined($v1) ? $v1 : defined($v2) ? $v2 : $v3;
                $settings{$directive} = $v;
            }
        }
        if ( %active_configs || %disabled_rules || %settings ) {
            $self->manipulate(
                sub {
                    my $data = shift;
                    @$data{qw(active_configs disabled_rules settings)} = ( \%active_configs, \%disabled_rules, \%settings );
                }
            );
        }
    };
    if ( my $exception = $@ ) {
        _restore_orig_modsec_cpanel_conf();
        die $exception;
    }
    return 1;
}

sub setup_defaults {
    my ($self) = @_;
    my %our_default_settings;
    for my $setting ( Whostmgr::ModSecurity::Settings::known_settings() ) {
        if ( defined $setting->{our_default} ) {
            $our_default_settings{ $setting->{directive} } = $setting->{our_default};
        }
    }
    if (%our_default_settings) {
        return $self->manipulate(
            sub {
                my $data = shift;
                $data->{settings} = \%our_default_settings;
            }
        );
    }
    return;
}

sub backup {
    my ($self) = @_;

    # If the datastore doesn't even exist yet, don't bother doing a backup, but don't
    # treat this as a complete failure either.
    return if !-f Whostmgr::ModSecurity::abs_modsec_cpanel_conf_datastore();

    my $rand = int rand 1e9;
    $self->{backup} = Whostmgr::ModSecurity::abs_modsec_cpanel_conf_datastore() . '.bak' . $rand;
    require File::Copy;
    File::Copy::copy( Whostmgr::ModSecurity::abs_modsec_cpanel_conf_datastore(), $self->{backup} )
      or die $!;
    return 1;
}

sub restore_backup {
    my ($self) = @_;
    if ( my $backup = $self->{backup} ) {
        rename $backup, Whostmgr::ModSecurity::abs_modsec_cpanel_conf_datastore()
          or die $!;
        unlink Whostmgr::ModSecurity::abs_modsec_cpanel_conf_datastore() . '.cache';
        delete $self->{backup};
        my $logger = Cpanel::Logger->new;
        $logger->info('Restored modsec_cpanel_conf_datastore backup');    # do not translate

        # Rebuild modsec2.cpanel.conf from the datastore restored above without changing anything else
        return $self->manipulate( sub { } );
    }
    return;
}

sub purge_backup {
    my ($self) = @_;
    if ( my $backup = $self->{backup} ) {
        unlink $backup
          or die $!;
        delete $self->{backup};
        return 1;
    }
    return;
}

sub ensure_secdatadir {
    my $dir = Whostmgr::ModSecurity::abs_secdatadir();
    if ( !-d Whostmgr::ModSecurity::abs_secdatadir() ) {

        my $nobody_gid = getgrnam('nobody') || die;

        # Create the directory owned by root:nobody and mode 770 with sticky bit.
        # This allows Apache to write to it as if it were /tmp, but prevents most
        # other processes from accessing it.
        Cpanel::Autodie::mkdir( Whostmgr::ModSecurity::abs_secdatadir(), 0700 );
        Cpanel::Autodie::chown( 0, $nobody_gid, Whostmgr::ModSecurity::abs_secdatadir() );
        Cpanel::Autodie::chmod( 01770, Whostmgr::ModSecurity::abs_secdatadir() );

        my $logger = Cpanel::Logger->new();
        $logger->info( lh()->maketext( q{You have successfully created the directory for [asis,SecDataDir]: [_1]}, Whostmgr::ModSecurity::abs_secdatadir() ) );
    }
    return 1;
}

sub _restore_orig_modsec_cpanel_conf {
    return rename _abs_mcc() . '.PREVIOUS', _abs_mcc();
}

sub _abs_mcc {
    return Whostmgr::ModSecurity::get_safe_config_filename( Whostmgr::ModSecurity::modsec_cpanel_conf() );
}

1;
