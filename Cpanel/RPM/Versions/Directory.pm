package Cpanel::RPM::Versions::Directory;

# cpanel - Cpanel/RPM/Versions/Directory.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Carp;

use Try::Tiny;

use Cpanel::Config::LoadCpConf        ();
use Cpanel::LoadModule                ();
use Cpanel::RPM::Versions::File::YAML ();
use Cpanel::SafeDir::MK               ();
use Cpanel::Update::Config            ();
use Cpanel::Update::Logger            ();
use Cpanel::Services::Enabled         ();
use Cpanel::MariaDB                   ();
use Cpanel::MysqlUtils::Versions      ();

our $RPM_VERSIONS_DIRECTORY = '/var/cpanel/rpm.versions.d';

sub new ( $class, $args = do { {} } ) {
    my $self = $class->init($args);

    bless $self, $class;

    if ( !-d $self->{'versions_directory'} ) {
        Cpanel::SafeDir::MK::safemkdir( $self->{'versions_directory'}, '0700', 2 );
    }

    # Detect when we're first installing cPanel. In that case, we disable mysql/nameserver targets until we can run setup on them.
    $self->{'bootstrapping'} = -e '/usr/local/cpanel/cpanel' ? 0 : 1;

    $self->load_local_file();
    $self->load_directory();

    $self->set_legacy() unless ( $args->{'dont_set_legacy'} );

    $self->load_cpupdate_conf();

    $self->disable_mysql_deps_for_cpanel_bootstrap();

    return $self;
}

sub _need_object ($self) {
    $self->isa(__PACKAGE__) or do {
        my @caller = caller(1);
        die("You must call $caller[3] as a method at $caller[1] line $caller[2].\n");
    };
    return;
}

sub init ( $class, $args ) {

    # note on mysql_targets, 50, 51 added back so we can "walk" a client up to
    # current mysqls from older ones.  They are not listed as options in the
    # GUI screens

    return {
        'logger'             => $args->{'logger'}        || Cpanel::Update::Logger->new(),
        'versions_directory' => $args->{'directory'}     || $RPM_VERSIONS_DIRECTORY,
        'local_file_name'    => $args->{'local_file'}    || 'local.versions',
        'updisabledir'       => $args->{'updisabledir'}  || '/etc',
        'mysql_targets'      => $args->{'mysql_targets'} || [ Cpanel::MysqlUtils::Versions::get_rpm_target_names( Cpanel::MysqlUtils::Versions::get_installable_versions() ) ],
        'versions_store'     => {},
        'cpconfig'           => scalar Cpanel::Config::LoadCpConf::loadcpconf(),
    };
}

sub cpconfig ($self) {
    _need_object($self);
    return $self->{'cpconfig'};
}

sub versions_directory ($self) {
    _need_object($self);
    return $self->{'versions_directory'};
}

sub local_file_name ($self) {
    _need_object($self);
    return $self->{'local_file_name'};
}

sub set ( $self, $args = undef ) {
    _need_object($self);

    $self->{'local_file_data'}->set($args);

    return;
}

sub delete ( $self, $args = undef ) {
    _need_object($self);

    $self->{'local_file_data'}->delete($args);

    return;
}

sub save ($self) {
    _need_object($self);

    $self->{'local_file_data'}->save();

    my $updisablefiles = $self->{'updisablefiles'} || [];

    foreach my $file (@$updisablefiles) {
        unlink $file;
    }

    if ( $self->{'changed'} ) {
        Cpanel::Update::Config::save( $self->{'update_config'} );
    }

    return;
}

sub fetch ( $self, $args ) {
    _need_object($self);

    my $section = $args->{'section'};
    my $key     = $args->{'key'};

    if ($key) {    # Supply from local file if present
                   # return versions_store if the local file doesn't exist.
        if ( !$self->{'local_file_data'} ) {
            return $self->{'versions_store'}{$section}{$key};
        }

        my $in_local_file = $self->{'local_file_data'}->fetch( { 'section' => $section, 'key' => $key } );
        if ($in_local_file) {    # The key exists in the local file.
            return $in_local_file;
        }
        else {                   # Supply from vendor aggregation
            return $self->{'versions_store'}{$section}{$key};
        }
    }
    else {

        # The versions_store section will always be there because legacy populates it.
        my %dir_section = %{ $self->{'versions_store'}{$section} || {} };

        # If no local file was loaded, then skip the reconcile.
        return \%dir_section if ( !$self->{'local_file_data'} );

        # pull in the local file
        my $local_section = $self->{'local_file_data'}->fetch( { 'section' => $section } );

        # Apply the local data to our dir section and return it.
        # TODO:  This will confuse save actions if this section is overwritten
        # Need to copy the hash?
        foreach my $key ( keys %{$local_section} ) {
            $dir_section{$key} = $local_section->{$key};
        }

        return \%dir_section;
    }
}

sub load_local_file ($self) {
    _need_object($self);

    my $local_file = $self->{'versions_directory'} . '/' . $self->local_file_name();
    $self->{'local_file_data'} = Cpanel::RPM::Versions::File::YAML->new( { file => $local_file } );

    # Strip out unknown states for target_settings so unexpected disabling of targets doesn't happen.
    my $data = $self->{'local_file_data'}->{'data'}->{'target_settings'};
    return unless $data && ref $data eq 'HASH';    # Nothing to do.
    foreach my $key ( sort keys %$data ) {
        my $value = $data->{$key};
        next if $value =~ m/^((un)?installed|unmanaged)$/;    # Nothing to clean up.
        delete $data->{$key};
        if ( $0 =~ m/update_local_rpm_versions/ ) {           # scripts/update_local_rpm_versions will actually save this change so our message needs to be different.
            $self->{'logger'}->warning("Unexpected value '$value' for target_settings.$key in $local_file. This is being fixed by removing the setting.");
        }
        else {                                                # Any reader will only remove the key for the life of this process. So we need to warn them and tell them how to fix it.
            $self->{'logger'}->warning("Unexpected value '$value' for target_settings.$key in $local_file. Ignoring this key.");
            $self->{'logger'}->warning("You can correct this by running: /usr/local/cpanel/scripts/update_local_rpm_versions --del target_settings.$key");
        }
    }

    return;
}

sub load_directory ($self) {
    _need_object($self);

    my $dir_fh;
    opendir( $dir_fh, $self->versions_directory() ) or do {
        my $message = 'Unable to load files in directory: ' . $self->versions_directory();
        $self->{'logger'}->fatal($message);
        die($message);
    };
    my @versions_files = map { $self->versions_directory() . '/' . $_ }
      grep { $self->local_file_name() ne $_ }
      grep { /\.versions$/ }
      grep { !/^\.\.?$/ } readdir($dir_fh);

    foreach my $file (@versions_files) {
        my $data;
        eval { $data = Cpanel::RPM::Versions::File::YAML->new( { file => $file } ) };

        # Skip any invalid YAML files found and log an error
        if ( !$data or ref $data ne 'Cpanel::RPM::Versions::File::YAML' ) {
            $self->{'logger'}->error("$@");
            next;
        }

        # Access the loaded YAML.
        $data = $data->{'data'};

        # Strip out unknown states for target_settings so unexpected disabling of targets doesn't happen.
        foreach my $key ( sort keys %{ $data->{'target_settings'} || {} } ) {
            my $value = $data->{'target_settings'}->{$key};
            next if $value =~ m/^((un)?installed|unmanaged)$/;
            delete $data->{'target_settings'}->{$key};
            $self->{'logger'}->warning("Unexpected value '$value' for target_settings.$key in $file. Ignoring this key.");
        }

        # TODO: If 2 vendor files have the same data in a conflicting key then it's not a conflict.
        # So we need to parse when we find this.
        foreach my $section ( keys %{$data} ) {
            next if ( $section eq 'file_format' );    # All files have a file format key. This isn't a conflict.
            foreach my $key ( keys %{ $data->{$section} } ) {
                my $in_local_file = $self->{'local_file_data'}->fetch( { 'section' => $section, 'key' => $key } );
                if ( defined $self->{'versions_store'}{$section}{$key} && !$in_local_file ) {    # Not in the local file
                                                                                                 # If the section and key have been set then the new data's section and key should not match if they aren't refs
                    if ( defined $data->{$section}{$key} ) {
                        if ( $section eq 'target_settings' && ( $self->{'versions_store'}{$section}{$key} eq 'uninstalled' && $data->{$section}{$key} eq 'installed' )
                            || ( $self->{'versions_store'}{$section}{$key} eq 'installed' && $data->{$section}{$key} eq 'uninstalled' ) ) {
                            my $message = "Conflict in section $section key $key [versions_store=$self->{'versions_store'}{$section}{$key}] [value=$data->{$section}{$key}] [file=$file]: installed will be used";
                            $self->{'logger'}->info($message);
                            $self->{'versions_store'}{$section}{$key} = 'installed';
                            next;
                        }
                        else {
                            my $message = "Conflict in section $section key $key [versions_store=$self->{'versions_store'}{$section}{$key}] [value=$data->{$section}{$key}] [file=$file]";
                            $self->{'logger'}->fatal($message);
                            die $message;
                        }
                    }
                }
                $self->{'versions_store'}{$section}{$key} = $data->{$section}{$key};
            }
        }
    }
    return;
}

sub disable_mysql_deps_for_cpanel_bootstrap ($self) {
    _need_object($self);

    # Only in initial install would this file not be present.
    return undef if !$self->{'bootstrapping'};

    # At least one Maria target needs to be resolving to installed.
    # set_mysql_targets is already doing the heavy lifting to determine that
    # MariaDB has been enabled in some way. We can just trust it.
    # This allows rpm.versions.d overrides to also be properly honored here.
    my $versions_store_targets = $self->{'versions_store'}{'target_settings'};
    return 0 unless ( grep { m/^maria/i && $versions_store_targets->{$_} && $versions_store_targets->{$_} eq 'installed' } @{ $self->{'mysql_targets'} } );

    return 1;
}

# Setup target_settings with legacy targets based on cpanel.config settings
sub set_legacy ($self) {
    _need_object($self);

    $self->set_dns_targets();
    $self->set_ftp_targets();
    $self->set_mysql_targets();

    return;
}

sub set_mysql_targets ($self) {
    _need_object($self);

    my $enabled_target = $self->cpconfig()->{'mysql-version'} || '';
    $enabled_target =~ s/\.//g;
    $enabled_target = ( Cpanel::MariaDB::version_is_mariadb($enabled_target) ? 'MariaDB' : 'MySQL' ) . $enabled_target;

    # ONLY 1 OF THESE CAN BE CHOSEN!!!
    foreach my $target ( @{ $self->{'mysql_targets'} } ) {

        # rpm.versions.d setting
        my $local_setting = $self->fetch( { 'section' => 'target_settings', 'key' => $target } );

        # Do not allow 'installed' if another MySQL is enabled in cpanel.config
        if ( $enabled_target ne $target && $local_setting ) {
            $local_setting =~ s/\binstalled\b/unmanaged/;
        }

        $self->{'versions_store'}{'target_settings'}{$target} = $local_setting || ( $enabled_target eq $target ? 'installed' : 'uninstalled' );
    }

    return;
}

sub set_dns_targets ($self) {
    _need_object($self);

    # Do not try to set the dns target during a base install. The setupnameserver script will handle this.
    my $enabled_target = ( Cpanel::Services::Enabled::is_enabled('dns') && !$self->{'bootstrapping'} ) ? ( $self->cpconfig()->{'local_nameserver_type'} || 'bind' ) : 'none';

    # Set all targets related to legacy dns.
    foreach my $target (qw/powerdns/) {

        # rpm.versions.d setting
        my $local_setting = $self->fetch( { 'section' => 'target_settings', 'key' => $target } );

        $self->{'versions_store'}{'target_settings'}{$target} = $local_setting || ( $enabled_target eq $target ? 'installed' : 'uninstalled' );
    }

    return 1;
}

sub set_ftp_targets ($self) {
    _need_object($self);

    my $enabled_target = Cpanel::Services::Enabled::is_enabled('ftp') ? ( $self->cpconfig()->{'ftpserver'} || '' ) : 'none';

    foreach my $target (qw/pure-ftpd proftpd/) {

        # rpm.versions.d setting
        my $local_setting = $self->fetch( { 'section' => 'target_settings', 'key' => $target } );

        $self->{'versions_store'}{'target_settings'}{$target} = $local_setting || ( $enabled_target eq $target ? 'installed' : 'uninstalled' );
    }

    return 1;
}

sub load_cpupdate_conf ($self) {
    _need_object($self);

    my @local_keys;

    my $config = Cpanel::Update::Config::load();

    # Get a list of up targets which are disabled at the moment. (keys will be the disabled items)
    my %update_is_disabled = map { tr/A-Z/a-z/; $_ =~ s/up$//; $_ => 1 } grep { $config->{$_} eq 'never' } keys %$config;

    $self->{'updisablefiles'} = [];

    foreach my $service (qw/ftp mysql exim/) {
        my $file = "$self->{'updisabledir'}/${service}updisable";
        if ( -e $file ) {
            $update_is_disabled{$service} = 1;
            push @{ $self->{'updisablefiles'} }, $file;
            $self->{'changed'} = 1;
        }
    }

    # exim
    push @local_keys, 'exim' if ( $update_is_disabled{'exim'} );

    # ftp
    my $ftp_server = $self->cpconfig()->{'ftpserver'};
    push @local_keys, $ftp_server if ( Cpanel::Services::Enabled::is_enabled('ftp') && $update_is_disabled{'ftp'} );

    # MySQL
    if ( $update_is_disabled{'mysql'} ) {
        my $version = $self->cpconfig()->{'mysql-version'};
        $version =~ s/\.//;
        push @local_keys, "MySQL$version";
    }

    # Set to unmanaged
    foreach my $key (@local_keys) {
        $self->set( { 'section' => 'target_settings', 'key' => $key, 'value' => 'unmanaged' } );
    }

    if (@local_keys) {
        my $message = "The following changes were made to your $self->{'versions_directory'}/local.versions file automatically due to =never settings in /etc/cpupdate.conf or *updisable touchfiles in /etc:\n\n";
        $message .= "$_: unmanaged\n" foreach (@local_keys);
        $message .= "\n cpupdate.conf is no longer the place to disable updates, nor is creating *updisable touchfiles in /etc an acceptable way to disable updates.\n";
        $message .= "If this was not your intention, you should remove this from local.versions.\n\n";
        $message .= "Example: In order to re-enable updates for proftpd you would do: /usr/local/cpanel/scripts/update_local_rpm_versions -del target_settings.proftpd\n\n";
        $message .= "Please refer to our documentation at https://go.cpanel.net/rpmversions for more information.\n";

        $self->{'logger'}->warning("Sending notification about changed settings in cpupdate.conf:\n\n$message\n");

        if ( try( sub { Cpanel::LoadModule::load_perl_module("Cpanel::iContact::Class::RPMVersions::Notify") } ) ) {
            require Cpanel::Notify;
            Cpanel::Notify::notification_class(
                'class'            => 'RPMVersions::Notify',
                'application'      => 'RPMVersions::Notify',
                'constructor_args' => [
                    'origin'             => 'RPMVersions::Directory',
                    'versions_directory' => $self->{'versions_directory'},
                    'local_keys'         => \@local_keys
                ]
            );
        }
        else {
            require Cpanel::iContact;
            Cpanel::iContact::icontact(
                'application' => 'rpm.versions',
                'subject'     => 'cpupdate.conf settings converted to local.versions',
                'message'     => $message,
            );
        }

    }

    foreach my $key ( keys %$config ) {
        next if ( $key =~ m/^(CPANEL|RPMUP|SARULESUP|UPDATES|STAGING_DIR)$/ );
        $self->{'changed'} = 1;
        delete $config->{$key};
    }

    $self->{'update_config'} = $config;

    return 1;
}

sub config_changed ($self) {
    _need_object($self);

    return $self->{'changed'} ? 1 : 0;
}

1;
