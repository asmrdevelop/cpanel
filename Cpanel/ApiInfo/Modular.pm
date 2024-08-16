package Cpanel::ApiInfo::Modular;

# cpanel - Cpanel/ApiInfo/Modular.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw(
  Cpanel::ApiInfo::Writer
);

use Cpanel::AccessIds::ReducedPrivileges  ();
use Cpanel::Alarm                         ();
use Cpanel::JSON                          ();
use Cpanel::LoadFile                      ();
use Cpanel::Transaction::File::JSONReader ();

our $TIMEOUT = 30;

my $FILE_FORMAT_VERSION = 1;

sub DIST_SPEC_FILE_PATH {
    my ($self) = @_;

    return $self->SYSTEM_SPEC_FILE_DIR() . '/' . $self->SPEC_FILE_BASE() . ".dist.json";
}

sub _get_public_data_from_datastore {
    my ( $self, $local_datastore ) = @_;

    my $dist_datastore = Cpanel::Transaction::File::JSONReader->new( path => $self->DIST_SPEC_FILE_PATH() );

    my $module_subs_hr = $dist_datastore->get_data()->{'module_subs'};

    my $local_data = $local_datastore->get_data();

    if ( ref $local_data eq 'HASH' ) {
        my $local_module_subs_hr = $local_data->{'module_subs'};
        @{$module_subs_hr}{ keys %$local_module_subs_hr } = values %$local_module_subs_hr;
    }

    return $module_subs_hr;
}

sub _update_transaction {
    my ( $self, $transaction ) = @_;

    my $file_data = $transaction->get_data();
    if ( !$file_data || ( ( 'SCALAR' eq ref $file_data ) && !$$file_data ) || $file_data->{'_version'} < $FILE_FORMAT_VERSION ) {
        $file_data = {
            _version    => $FILE_FORMAT_VERSION,
            _file_mtime => {},
            module_subs => {},
        };
    }
    my $file_mtime_hr  = $file_data->{'_file_mtime'};
    my $module_subs_hr = $file_data->{'module_subs'};

    my $module_mtime_hr = $self->_get_module_mtime_hr();

    my $need_save;

    my %new_module_subs;

    my $privs = Cpanel::AccessIds::ReducedPrivileges->new('nobody');
    require Cpanel::Env;
    Cpanel::Env::clean_env();
    while ( my ( $path, $current_mtime ) = each %$module_mtime_hr ) {
        my $old_mtime = $file_mtime_hr->{$path} || 0;

        $path =~ m{/([^/]+).pm\z};
        my $module = $1;

        #Only accept equal mtimes; if the old mtime is somhow greater than
        #the current one, assume something is wrong and we need to rebuild.
        if ( $old_mtime == $current_mtime ) {
            if ( exists $module_subs_hr->{$module} ) {
                $new_module_subs{$module} = $module_subs_hr->{$module};
            }
        }
        else {
            $need_save = 1;

            my $subs_ar = $self->find_subs_in_path_ar($path);

            #This has to be here; otherwise a module with no API functions
            #will be searched each time.
            $file_mtime_hr->{$path} = $current_mtime;

            if ( $subs_ar && @$subs_ar ) {
                $new_module_subs{$module} = [ sort @$subs_ar ];
            }
        }
    }

    my @deleted_paths = grep { !$module_mtime_hr->{$_} } keys %$file_mtime_hr;
    if (@deleted_paths) {
        $need_save = 1;
        delete @{$file_mtime_hr}{@deleted_paths};
    }

    if ($need_save) {
        $file_data->{'module_subs'} = \%new_module_subs;
        $transaction->set_data($file_data);
    }

    return $need_save ? 1 : 0;
}

sub _get_module_mtime_hr {
    my ($self) = @_;

    my $modules_dir = $self->MODULES_DIR();

    opendir( my $ulcc_dh, $modules_dir ) or die "Cannot open $modules_dir: $!";

    my %module_mtime;
    while ( my $file = readdir $ulcc_dh ) {
        next if $file !~ m{\.pm\z};
        my $path = "$modules_dir/$file";
        $module_mtime{$path} = ( stat $path )[9];
    }

    closedir $ulcc_dh;

    return \%module_mtime;
}

sub _clone_public_data_from_datastore {
    my ( $self, $ds_data ) = @_;

    return Cpanel::JSON::Load( Cpanel::JSON::Dump( $ds_data->get_data()->{'module_subs'} ) );
}

sub _load_module_text_sr {
    my ( $self, $module, $path ) = @_;
    my $perl_code = Cpanel::LoadFile::loadfile($path) or do {
        warn "Could not load file $path: $!";
        return 0;
    };

    if ( $perl_code =~ m/\#\s*cp_no_verify/ ) {
        warn "Skipping ${module}, #cp_no_verify comment detected.\n";
        return 0;
    }

    return \$perl_code;
}

# Load the module, suppress output, provide timeout
#
# return 0 if it failed to load
# return module contents if it succeeded
sub _load_module {
    my ( $self, $module, $path ) = @_;

    delete $INC{$path} if exists $INC{$path};

    # Suppress STDERR output to suppress warnings
    open my $old_stderr, '>&', \*STDERR    or warn 'Could not redirect STDERR';
    open STDERR,         '>',  '/dev/null' or warn 'Could not redirect STDERR';

    eval {
        # Timeout module load in case 3rdparty module relies on external resource
        my $timeout_action = sub { die 'timeout while loading module' };
        my $alarm          = Cpanel::Alarm->new( $TIMEOUT, $timeout_action );
        require $path;
    } or do {
        open STDERR, '>&', \$old_stderr or warn 'Could not restore STDERR';
        warn "Error loading module in “$path”: $@" if $@ !~ m{Can't locate};
        return 0;
    };

    open STDERR, '>&', \$old_stderr or warn 'Could not restore STDERR';
    return 1;
}

1;
