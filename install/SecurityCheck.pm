package Install::SecurityCheck;

# cpanel - install/SecurityCheck.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw( Cpanel::Task );

use File::Find                   ();
use Cpanel::SafetyBits           ();
use Cpanel::FileUtils::Link      ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics

our $VERSION = '1.2';

=head1 DESCRIPTION

    Runs multiple setup/purge scripts:
    - bin/purge_old_datastores
    - bin/resetcaches
    - bin/hulkdsetup
    - bin/cpsessetup

    Fix permissions and ownership of multiple directories

    Cleanup /var/cpanel/passtokens directory.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('securitycheck');

    return $self;
}

sub _create_directory {
    my $name = shift;
    my $dir  = "/var/cpanel/$name";

    if ( !-e $dir ) {
        mkdir $dir;
        chmod 0700, $dir;
        Cpanel::SafetyBits::safe_chown( 'cpanel', 'cpanel', $dir );
    }

    return 1;
}

sub _fix_permissions {
    my @files = (
        '/usr/local/cpanel/3rdparty/share/Counter/data',
        '/usr/local/cpanel/base/tmp',
        '/var/spool/mail',
        '/var/spool/vbox',
        '/usr/local/apache/proxy',
        '/var/lib/texmf',
        '/var/spool/samba'
    );

    foreach my $file (@files) {
        if ( -e $file ) {
            chmod 0755, $file;
        }
    }
    return 1;
}

sub _mode_to_octal_mode {
    my $mode  = shift;
    my $omode = sprintf "%#03o", $mode & 07777;
    return $omode;
}

sub _remove_world_write {
    my $file = shift;

    return unless defined $file;
    my $mode    = ( stat $file )[2] // 0;
    my $newmode = ( $mode & 002 ) ? ( $mode ^ 002 ) : $mode;

    if ( $mode != $newmode ) {
        my $newperms = _mode_to_octal_mode($newmode);
        return chmod( oct $newperms ), $file;
    }

    return 1;
}

sub _secure_files {
    my @files = (
        '/var/cpanel/accounting.log',
        '/usr/local/cpanel/logs/login_log',
        '/usr/local/cpanel/logs/license_log',
    );

    foreach my $file (@files) {
        next unless -e $file;
        Cpanel::SafetyBits::safe_chown 'root', -1, $file;
        chmod 0600, $file;
    }

    return 1;
}

sub _unlink_standardnews {
    if ( $File::Find::topdir eq $File::Find::name ) {
        return;
    }
    elsif ( -d $File::Find::name ) {
        $File::Find::prune = 1;
        return;
    }

    if ( /standardnews$/
        && !Cpanel::FileUtils::Link::safeunlink($File::Find::name) ) {
        warn 'Unable to unlink ' . $File::Find::name;
    }

    return;
}

sub _chmod_0600 {
    if ( $File::Find::topdir eq $File::Find::name ) {
        return;
    }
    elsif ( -d $File::Find::name ) {
        $File::Find::prune = 1;
        return;
    }

    if (/\.accts$/) {
        chmod 0600, $File::Find::name;
    }

    return;
}

sub _remove_old_securityquestions {
    my @files = ('/usr/local/cpanel/Cpanel/SecurityPolicy/SecurityQuestions.pm');
    foreach my $file (@files) {
        if ( -e $file ) {
            unlink $file or warn "Failed to unlink file $file: $!";
        }
    }

    return;
}

sub _remove_passtokens {
    if ( $File::Find::topdir eq $File::Find::name ) {
        return;
    }
    elsif ( -d $File::Find::name ) {
        $File::Find::prune = 1;
        return;
    }

    if (/\.token\./) {
        unlink $File::Find::name;
    }
    return;
}

sub perform {
    my $self = shift;

    {
        require '/usr/local/cpanel/bin/purge_old_datastores';    ##no critic qw(RequireBarewordIncludes)
        local $@;
        eval { bin::purge_old_datastores->script(); };
        warn if $@;
    }

    {
        require '/usr/local/cpanel/bin/resetcaches';             ##no critic qw(RequireBarewordIncludes)
        local $@;
        eval { bin::resetcaches->script(); };
        warn if $@;
    }

    _create_directory('.cpanel');
    _create_directory('tmp');

    require '/usr/local/cpanel/bin/hulkdsetup';      ##no critic qw(RequireBarewordIncludes)
    local $@;
    eval { bin::hulkdsetup::run('--noreload'); };    # will get restarted from etc/init/startup
    warn if $@;

    require '/usr/local/cpanel/bin/cpsessetup';      ##no critic qw(RequireBarewordIncludes)
    eval { bin::cpsessetup->script(); };
    warn if $@;

    if ( -e '/var/lib/mysql' ) {
        chmod 0751, '/var/lib/mysql';
    }
    if ( -e '/var/db/mysql' ) {
        chmod 0751, '/var/db/mysql';
    }

    File::Find::find( \&_unlink_standardnews, '/usr/local/cpanel/whostmgr/bin' );

    _remove_old_securityquestions();

    Cpanel::SafetyBits::safe_chown 'root', 10, '/usr/local/cpanel';

    # During the early run of this task, apache may not yet be installed
    if ( -d apache_paths_facade->dir_domlogs() ) {
        Cpanel::SafetyBits::safe_chown 'root', 10, apache_paths_facade->dir_domlogs();
        chmod 0711, apache_paths_facade->dir_domlogs();
    }

    chmod 0711, '/home/virtfs';

    if ( !-e '/var/cpanel/version/src_chmod' && -e '/usr/local/cpanel/src' ) {
        File::Find::find( \&_remove_world_write, '/usr/local/cpanel/src' );
        Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/version/src_chmod');
    }

    _fix_permissions();

    require '/usr/local/cpanel/bin/checksshconf';    ##no critic qw(RequireBarewordIncludes)
    {
        local $@;
        eval { bin::checksshconf->script(); };
        warn if $@;
    }

    _secure_files();

    if ( -e q[/var/cpanel/passtokens] ) {
        File::Find::find( \&_remove_passtokens, '/var/cpanel/passtokens' );
    }

    return 1;
}

1;

__END__
