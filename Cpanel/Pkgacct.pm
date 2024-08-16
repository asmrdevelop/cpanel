package Cpanel::Pkgacct;

# cpanel - Cpanel/Pkgacct.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Context                ();
use Cpanel::FileUtils::Dir         ();
use Cpanel::Autodie                ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Exception              ();
use Cpanel::Fcntl                  ();
use Cpanel::FHUtils::Blocking      ();
use Cpanel::SafeSync               ();
use Cpanel::SafeRun::Object        ();
use Cpanel::SafeDir::MK            ();
use Cpanel::SimpleSync::CORE       ();
use Cpanel::Umask                  ();
use Cpanel::LoadModule             ();
use Cpanel::ForkAsync              ();
use Cpanel::Output                 ();
use Cpanel::LoadModule::Name       ();
use Cpanel::IOCallbackWriteLine    ();
use Cpanel::AdminBin::Serializer   ();

use Try::Tiny;

use parent 'Cpanel::AttributeProvider';

use constant PKGTREE_DIRS => qw(
  apache_tls
  bandwidth
  bandwidth_db
  counters
  cp
  cron
  customizations
  dnszones
  domainkeys
  domainkeys/private
  domainkeys/public
  httpfiles
  ips
  locale
  logs
  meta
  mm
  mma
  mma/priv
  mma/pub
  mms
  mysql
  mysql-timestamps
  psql
  resellerconfig
  resellerfeatures
  resellerpackages
  sslcerts
  sslkeys
  ssl
  suspended
  suspendinfo
  userdata
  va
  vad
  vf
  team
);

my $COMPONENT_PATH = '/usr/local/cpanel/Cpanel/Pkgacct/Components';

# All of this feels very hacky. I don't like how these output objects are set up
# but I currently cannot think of a way of rearranging all of this without gutting
# the whole output object system.
# TODO: refactor Cpanel::Output to allow
#   ->output_timestamp
#   ->output_partial_timestamp
#   ->output_partial
our @NOT_PARTIAL_TIMESTAMP = ( $Cpanel::Output::SOURCE_NONE, $Cpanel::Output::COMPLETE_MESSAGE, $Cpanel::Output::PREPENDED_MESSAGE );
our @PARTIAL_TIMESTAMP     = ( $Cpanel::Output::SOURCE_NONE, $Cpanel::Output::PARTIAL_MESSAGE,  $Cpanel::Output::PREPENDED_MESSAGE );
our @PARTIAL_MESSAGE       = ( $Cpanel::Output::SOURCE_NONE, $Cpanel::Output::PARTIAL_MESSAGE,  $Cpanel::Output::NOT_PREPENDED_MESSAGE );

#XXX: Called directly from tests
use constant _required_properties => qw(
  OPTS
  cpconf
  dns_list
  domains
  is_backup
  is_incremental
  is_userbackup
  new_mysql_version
  now
  output_obj
  suspended
  uid
  user
  work_dir
);

use constant _optional_properties => ();

###########################################################################
#
# Method:
#   new
#
# Description:
#   Create a pkgacct component object
#
#
sub new {
    my ( $class, %OPTS ) = @_;

    my $self = bless {}, $class;

    foreach my $required_opt ( $self->_required_properties() ) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required_opt ] ) if !defined $OPTS{$required_opt};
    }

    $self->import_attrs( { map { $_ => $OPTS{$_} } $class->_accepted_properties() } );    ## no critic (ProhibitVoidMap)

    # optional parms
    #
    # link_dest is an optional parameter for rsync, where rsync will do a 3
    # way compare and use hard links if possible, signficantly reducing the
    # size of the backup
    #

    if ( exists $OPTS{'OPTS'} && ref( $OPTS{'OPTS'} ) eq 'HASH' && length $OPTS{'OPTS'}{'link_dest'} && -d $OPTS{'OPTS'}{'link_dest'} ) {
        $self->{'link_dest'} = $OPTS{'OPTS'}{'link_dest'};
    }

    return $self;
}

sub _accepted_properties {
    my ($self) = @_;

    return (
        $self->_required_properties(),
        $self->_optional_properties(),
    );
}

###########################################################################
#
# Method:
#   perform_component
#
# Description:
#   The workhorse method of the component based pkgacct system. This method will load the
#   named component and run the perform() function of that component.
#
# Parameters:
#   $component - The name of a pkgacct component to run the perform method on.
#
# Exceptions:
#   Cpanel::Exception::IO::WriteError - Thrown if the print call fails in Cpanel::Autodie::print.
#
# Returns:
#   The method will return whatever the perform() method of the supplied component name returns.
#
sub perform_component {
    my ( $self, $component ) = @_;

    my $output_obj = $self->get_output_obj();
    $output_obj->out( "Performing “$component” component....", @NOT_PARTIAL_TIMESTAMP );

    my @ret;

    try {
        my $object = $self->get_component_object($component);
        @ret = $object->perform();
    }
    catch {
        push @{ $self->{'failed_components'} }, $component;

        require Cpanel::Exception;

        $output_obj->error( "The “$component” component failed with an error: " . Cpanel::Exception::get_string($_) . "\n", @NOT_PARTIAL_TIMESTAMP );
    };

    $output_obj->out( "Completed “$component” component.\n", @NOT_PARTIAL_TIMESTAMP );

    return @ret;
}

sub get_failed_components ($self) {
    Cpanel::Context::must_be_list();

    my $ar = $self->{'failed_components'};
    return $ar ? @$ar : ();
}

# Refactored from pkgacct script.
sub syncfile_or_warn {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $self, $source, $dest, $no_sym, $no_chown, $resume ) = @_;

    my ( $ok, $why ) = Cpanel::SimpleSync::CORE::syncfile( $source, $dest, $no_sym, $no_chown // 1, $resume );
    $self->get_output_obj()->warn($why) if !$ok;

    return;
}

sub get_component_object {
    my ( $self, $component ) = @_;
    my $module = "Cpanel::Pkgacct::Components::$component";
    Cpanel::LoadModule::load_perl_module($module);
    return "$module"->new(
        %{ $self->get_attrs() },
        pkgacct_obj => $self,
    );
}

sub get_work_dir {
    my ($self) = @_;
    return $self->get_attr('work_dir');
}

sub get_user {
    my ($self) = @_;
    return $self->get_attr('user');
}

sub get_domains {
    my ($self) = @_;
    return $self->get_attr('domains');
}

sub get_new_mysql_version {
    my ($self) = @_;
    return $self->get_attr('new_mysql_version');
}

sub get_uid {
    my ($self) = @_;
    return $self->get_attr('uid');
}

sub get_suspended {
    my ($self) = @_;
    return $self->get_attr('suspended');
}

sub get_is_incremental {
    my ($self) = @_;
    return $self->get_attr('is_incremental');
}

sub get_is_backup {
    my ($self) = @_;
    return $self->get_attr('is_backup');
}

sub get_is_userbackup {
    my ($self) = @_;
    return $self->get_attr('is_userbackup');
}

sub get_dns_list {
    my ($self) = @_;
    return $self->get_attr('dns_list');
}

sub get_now {
    my ($self) = @_;
    return $self->get_attr('now');
}

sub get_output_obj {
    my ($self) = @_;
    return $self->get_attr('output_obj');
}

sub get_OPTS {
    my ($self) = @_;
    return $self->get_attr('OPTS');
}

sub get_cpconf {
    my ($self) = @_;
    return $self->get_attr('cpconf');
}

sub get_cpuser_data {
    my ($self) = @_;

    return Cpanel::Config::LoadCpUserFile::load_or_die( $self->get_attr('user') );
}

###########################################################################
#
# Method:
#   file_needs_backup (please read XXX below before using)
#
# Description:
#   This method determines if a provided file path in an incremental backup needs to be refreshed from
#   the file's source location.
#
# Parameters:
#   $source_file - The path to a source file to check if it needs to be backed up to $target_file
#   $target_file - The path to a file or location for the source file to be backed up to.
#   $name        - The filename of the file to determine if it needs backed up.
#
# Exceptions:
#   Cpanel::Exception::IO::WriteError - Thrown if the print call fails in Cpanel::Autodie::print.
#
# Returns:
#   The method will return 1 if the source file needs to be backed up and 0 if the source file does not.
#
# ----------------------------------------------------------------------
# XXX THINK TWICE BEFORE USING THIS. The ideal is for Pkgacct to talk to
# *modules* rather than to read things directly from disk. This allows
# the data’s storage mechanism to change without breaking Pkgacct.
# If you use a function like this you’re probably tightly coupling Pkgacct
# to the internal storage implementation of whatever you’re backing up.
#
# A better design is to have the datastore module expose an mtime
# and then use mtime_needs_backup() with that.
#
sub file_needs_backup {
    my ( $self, $source_file, $target_file, $name ) = @_;

    $name ||= $source_file;

    my $last_update_time = ( stat($source_file) )[9];

    return $self->mtime_needs_backup( $last_update_time, $target_file, $name );
}

# Like file_needs_backup(), but accepts an mtime rather than a file.
sub mtime_needs_backup {
    my ( $self, $last_update_time, $target_file, $name ) = @_;

    die 'Need “name”!' if !$name;

    return 1 if !$self->get_is_incremental();
    return 1 if !-e $target_file || -z _;       #check for failed backups

    my $target_file_mtime = ( stat(_) )[9];

    return 1 if ( !$last_update_time
        || $last_update_time > $target_file_mtime
        || $last_update_time > time() );

    my $last_update_time_localtime  = localtime($last_update_time);
    my $target_file_mtime_localtime = localtime($target_file_mtime);

    Cpanel::Autodie::print("$name skipped (last change @ $last_update_time_localtime, current backup @ $target_file_mtime_localtime)\n");

    return 0;    #no need to backup again
}

###########################################################################
#
# Method:
#   ensure_dir_at_target
#
# Description:
#   Creates a directory if it does not exist at relative path
#   inside the work directory
#
# Parameters:
#   $reldir - The relative path for the directory
#   $perms  - The unix permissions for the directory
#
# Exceptions:
#   IO::DirectoryCreateError or ChmodError
#
# Returns:
#   1 on success
#

sub ensure_dir_at_target {
    my ( $self, $reldir, $perms ) = @_;

    my $work_dir = $self->get_work_dir();

    if ( !-d "$work_dir/$reldir" ) {
        local $!;

        #NOTE: safemkdir() doesn’t do a umask reset,
        #as a consequence of which we chmod() below even if
        #we also did safemkdir().
        #
        Cpanel::SafeDir::MK::safemkdir( "$work_dir/$reldir", $perms ) or die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ error => $!, path => "$work_dir/$reldir", mask => $perms ] );
    }

    Cpanel::Autodie::chmod( $perms, "$work_dir/$reldir" );

    return 1;
}

###########################################################################
#
# Method:
#   backup_dir_if_target_is_older_than_source
#
# Description:
#   Create a backup of a directory tree $source at $target
#   if anything in $target is older than $source
#
# Parameters:
#   $source_dir     - The source dir (an absolute path)
#   $rel_target_dir - The target dir, relative to the archive root.
#
# Returns:
#   A hashref of files owned by other uids (see Cpanel::SafeSync::safesync)
#

sub backup_dir_if_target_is_older_than_source {
    my ( $self, $source_dir, $rel_target_dir ) = @_;

    my $work_dir = $self->get_work_dir();

    $self->ensure_dir_at_target( $rel_target_dir, 0700 );

    my $is_backup      = $self->get_is_backup();
    my $is_userbackup  = $self->get_is_userbackup();
    my $is_incremental = $self->get_is_incremental();
    my $dest_dir       = $work_dir . '/' . $rel_target_dir;

    if ( !Cpanel::FileUtils::Dir::directory_has_nodes($source_dir) && !Cpanel::FileUtils::Dir::directory_has_nodes($dest_dir) ) {

        # Nothing to do avoid the fork/exec of safesync
        return 1;
    }

    return Cpanel::SafeSync::safesync(
        'source'   => $source_dir,
        'dest'     => $dest_dir,
        'isbackup' => ( $is_backup || $is_userbackup ),
        'delete'   => $is_incremental,
        'verbose'  => 0,
        'user'     => 'root',
    );
}

sub run_admin_backupcmd {
    my ( $self, @cmd )  = @_;
    my ( $prog, @args ) = @cmd;

    my $output_obj = $self->get_output_obj();
    my $run        = Cpanel::SafeRun::Object->new(
        program => $prog,
        args    => \@args,
        stderr  => Cpanel::IOCallbackWriteLine->new( sub { $output_obj->warn( shift, @Cpanel::Pkgacct::NOT_PARTIAL_MESSAGE ); } ),
    );

    if ( $run->CHILD_ERROR() ) {
        $output_obj->warn( 'Error while executing: [' . join( ' ', $prog, @args ) . ']: ' . $!, @NOT_PARTIAL_TIMESTAMP );
    }

    return Cpanel::AdminBin::Serializer::Load( $run->stdout() );
}

# TODO: relocated from pkgacct, needs docs
sub system_to_output_obj {
    my ( $self, $prog, @args ) = @_;
    my $output_obj = $self->get_output_obj();

    my $run = Cpanel::SafeRun::Object->new(
        program => $prog,
        args    => \@args,
        stdout  => Cpanel::IOCallbackWriteLine->new( sub { $output_obj->out( shift, @Cpanel::Pkgacct::NOT_PARTIAL_MESSAGE ); } ),
        stderr  => Cpanel::IOCallbackWriteLine->new( sub { $output_obj->warn( shift, @Cpanel::Pkgacct::NOT_PARTIAL_MESSAGE ); } ),
    );

    if ( $run->CHILD_ERROR() ) {
        return 0;
    }

    return 1;
}

# TODO: relocated from pkgacct, needs docs
# TODO: Cpanel::Pkgacct::Components::Mysql::_check_error_file would be nice as a generic module
# along with Cpanel::Pkgacct::exec_into_file and Cpanel::Pkgacct::simple_exec_into_file
sub exec_into_file {
    my ( $self, $file, $file_write_mode, $cmd_ref, $unlink ) = @_;
    my $begin_point = -1;
    my $end_point   = -1;
    my $status      = 0;

    # We want to avoid overwriting backups that may be hard linked together.
    unlink $file if $unlink && $file_write_mode eq ">";

    if ( open( my $fh, $file_write_mode, $file ) && open( my $err_fh, '>', $file . '.err' ) ) {
        $begin_point = tell($fh);
        my ( $program, @args ) = @$cmd_ref;
        my $run = Cpanel::SafeRun::Object->new(
            'stdout'       => $fh,
            'stderr'       => $err_fh,
            'program'      => $program,
            'args'         => \@args,
            'timeout'      => 86400,
            'read_timeout' => 86400,
        );
        if ( $run->CHILD_ERROR() ) {
            $status = $run->CHILD_ERROR();
            warn "exec($program @args) exited with error: " . $run->autopsy();
        }

        # Seek to the end of the file
        seek( $fh, 0, 2 );
        $end_point = tell($fh);
        close($fh);
    }
    else {
        warn "Failed to open exec_file: $file: $!";
    }

    return ( $begin_point, $end_point, $status );
}

# TODO: relocated from pkgacct, needs docs
# TODO: Cpanel::Pkgacct::Components::Mysql::_check_error_file would be nice as a generic module
# along with Cpanel::Pkgacct::exec_into_file and Cpanel::Pkgacct::simple_exec_into_file
sub simple_exec_into_file {
    my ( $self, $file, $cmdref ) = @_;

    #TODO: Reimplement using Cpanel::SafeRun::Object and
    #Cpanel::IOCallbackWriteLine or some other mechanism
    #that provides comprehensive error checking.

    if ( sysopen( my $fh, $file, Cpanel::Fcntl::or_flags(qw(O_WRONLY O_CREAT O_NOFOLLOW O_TRUNC)), 0600 ) ) {
        if ( my $pid = fork() ) {
            waitpid( $pid, 0 );
        }
        else {
            open( STDOUT, '>&=' . fileno($fh) );    ##no critic qw(ProhibitTwoArgOpen RequireCheckedOpen)
            { exec(@$cmdref); }
            exit 1;
        }
        close($fh);
    }
    return;
}

# TODO: relocated from pkgacct, needs docs
sub run_dot_event {    #uses a self pipe to finish instantly
    my ( $self, $code ) = @_;

    my $output_obj = $self->get_output_obj();

    #TODO: Audit for error response. This is core functionality
    #that should be as informative about failures as possible.

    # Setup a pipe so we can write a zero to the parent on SIGCHLD
    # (see the select on $rin below)  This will cause our select
    # below to trigger when the signal is received (usually a child exit).
    my ( $read_handle, $write_handle );
    pipe( $read_handle, $write_handle );

    Cpanel::FHUtils::Blocking::set_non_blocking($read_handle);
    Cpanel::FHUtils::Blocking::set_non_blocking($write_handle);

    local $SIG{'CHLD'} = sub {
        syswrite( $write_handle, '0', 1 );
    };
    my ( $rin, $nfound ) = ( q{}, undef );
    vec( $rin, fileno($read_handle), 1 ) = 1;

    my $original_pname = $0;

    my $pid = Cpanel::ForkAsync::do_in_child(
        sub {
            $0 = $original_pname . ' - subprocess';
            local $SIG{'CHLD'} = 'DEFAULT';    #very important or we will pollute the parent
            exit( $code->() );
        }
    );

    local $0 = $original_pname . ' - waiting for subprocess: ' . $pid;
    my $buffer;

    local $?;

    ## *** Please see case 44803 before making any changes below
    ## We previously saw waitpid($pid,0) finishing before we expected
    ## when SIGSTOP/SIGCONT is sent to the process group. ***
    until ( ( my $child = waitpid( $pid, 1 ) ) == $pid ) {
        last if $child == -1;

        $output_obj->out(".........\n");
        ## select with a timeout of 5s for the printed dots
        ## select on $rin, checking for a true value, as the syswrite
        ## on SIGCHLD will pop out of the select immediately
        if ( $nfound = select( $rin, undef, undef, 5 ) ) {

            # flush out the '0's we got from the pipe
            # when there is data on the pipe (from CHLD handler)
            # XXX: Should this not be sysread()??
            read( $read_handle, $buffer, 4096 );
        }
    }

    return $?;
}

# TODO: relocated from pkgacct, needs docs
sub build_pkgtree {
    my ( $self, $work_dir ) = @_;

    my $umask = Cpanel::Umask->new(0);

    Cpanel::Autodie::mkdir_if_not_exists( $work_dir, 0700 );

    foreach my $dir ( PKGTREE_DIRS() ) {
        my $full_dir = "$work_dir/$dir";

        Cpanel::Autodie::mkdir_if_not_exists( $full_dir, 0700 );
    }

    return;
}

sub load_all_components {
    my @modules = Cpanel::LoadModule::Name::get_module_names_from_directory($COMPONENT_PATH);

    foreach my $component (@modules) {
        my $module = "Cpanel::Pkgacct::Components::$component";
        Cpanel::LoadModule::load_perl_module($module);
    }

    return;
}

1;
