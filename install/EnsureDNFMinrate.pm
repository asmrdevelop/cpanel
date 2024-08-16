package Install::EnsureDNFMinrate;

# cpanel - install/EnsureDNFMinrate.pm              Copyright 2022 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

use parent qw( Cpanel::Task );

use cPstrict;

use Cpanel::Autodie ();
use Cpanel::OS      ();

use Path::Tiny ();

our $VERSION = '1.0';

=head1 DESCRIPTION

Ensure that dnf.conf is configured with a sane minrate setting.  This setting
replaces what fastestmirror was designed to do on systems using yum as a
package manager

=head1 SEE ALSO

L<Information regarding fastestmirror pluging for yum|https://wiki.centos.org/PackageManagement/Yum/FastestMirror>,
L<Information regarding minrate configuration option for dnf|https://dnf.readthedocs.io/en/latest/conf_ref.html#minrate-label>

=over 1

=item Type: Fresh Install, Sanity

=item Frequency: always

=item EOL: never

=back

=cut

our $dnf_config_file = '/etc/dnf/dnf.conf';
our $minrate         = '50k';

exit __PACKAGE__->runtask() unless caller;

sub new ($proto) {

    my $self = $proto->SUPER::new;
    $self->set_internal_name('ensure_dnf_minrate');

    return $self;
}

sub perform ($self) {

    return 1 unless Cpanel::OS::package_manager() eq 'dnf';
    return 1 unless Cpanel::Autodie::exists($dnf_config_file);

    $self->ensure_dnf_minrate();

    return 1;
}

sub ensure_dnf_minrate ($self) {

    my $dnf_path         = Path::Tiny::path($dnf_config_file);
    my @dnf_config_lines = $dnf_path->lines();
    chomp(@dnf_config_lines);

    # If it is already in the file, leave it be
    # since we do not want to step on customizations
    # Otherwise, add the line
    my $found = 0;
    foreach my $line (@dnf_config_lines) {
        next unless $line =~ /^\s*minrate\s*=/a;
        $found = 1;
        last;
    }
    push @dnf_config_lines, "minrate=$minrate" unless $found;

    my $dnf_config = join( "\n", @dnf_config_lines );
    $dnf_config .= "\n";
    $dnf_path->spew($dnf_config);

    return 1;
}

1;
