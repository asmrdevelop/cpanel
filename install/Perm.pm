package Install::Perm;

# cpanel - install/Perm.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use base qw( Cpanel::Task );

use File::Glob ();
use File::Find ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::SafetyBits ();

our $VERSION = '1.1';

=head1 DESCRIPTION

    Fixes permissions and owner of different files and directories.

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

    $self->set_internal_name('perm');

    return $self;
}

sub _chown_root_10() {
    return chown 0, 10, $File::Find::name;
}

sub _chown_root_10_cgi() {
    return if $File::Find::topdir eq $File::Find::name;
    return if -l $File::Find::name;
    if ( -d $File::Find::name ) {
        return $File::Find::prune = 1;
    }
    elsif ( $File::Find::name =~ /\.cgi$/ ) {
        return Cpanel::SafetyBits::safe_chown( 'root', 10, $File::Find::name );
    }
}

sub perform ($self) {

    if ( !-l '/usr/local/cpanel/cpsrvd.so' ) {
        Cpanel::SafetyBits::safe_chown 'root', 'cpanel', '/usr/local/cpanel/cpsrvd.so';
        chmod 0750, '/usr/local/cpanel/cpsrvd.so';
    }

    # Used to be in checkperm, called whenever cpsrvd restarted.
    chmod( oct(4755), '/usr/bin/quota' );

    chmod 0751, '/usr/local/cpanel/cgi-sys/';

    my @files = (
        '/etc/domainalias',
        '/usr/local/cpanel/cgi-sys/autodiscover.cgi',
        '/var/cpanel/mainips',
        apache_paths_facade->bin_suexec() . '.disable',
    );

    foreach my $file (@files) {
        chmod 0755, $file;
    }

    my $spamassassin_dir = '/etc/mail/spamassassin';
    foreach my $file ( File::Glob::bsd_glob("$spamassassin_dir/*.cf"), File::Glob::bsd_glob("$spamassassin_dir/*.pre") ) {
        chmod( 0644, $file );
    }

    chmod 0711, '/usr/local/cpanel';

    File::Find::find( \&_chown_root_10,     '/usr/local/cpanel/cgi-sys' );
    File::Find::find( \&_chown_root_10_cgi, '/usr/local/cpanel/base' );

    #
    # Required to figure out if we are on a dedicated ip address
    # We may do this with IO::Interface in the future
    #
    #
    if ( -e '/sbin/ip' ) {
        system 'chmod', 'a+x', '/sbin/ip';
    }

    return 1;
}

1;

__END__
