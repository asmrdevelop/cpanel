package Cpanel::Parser::DpkgQuery;

# cpanel - Cpanel/Parser/DpkgQuery.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Binaries::Debian::DpkgQuery ();

sub parse_string ($string) {
    my ( %packages, $cur_package );
    my $take_first_as = sub ($name) {
        return sub { $packages{$cur_package}{$name} = shift };
    };

    my $take_joined_as = sub ($name) {
        return sub { $packages{$cur_package}{$name} = join ' ', @_ };
    };

    my $take_all_as = sub ($name) {
        return sub { $packages{$cur_package}{$name} = [@_] },;
    };

    my $take_deplist_as = sub ($name) {
        return sub {

            # We can't tell for sure whether there will be a version definition
            # so we need to grab each and check for a version definition for it

            # We split every ahead of time, which is probably not the best approach
            # because it bites us here... well, let's fix it
            my $deplist_string = join ' ', @_;
            my @pkgs = split /[,|]/xms, $deplist_string;
            s/^\s+//xms for @pkgs;
            s/\s+$//xms for @pkgs;

            # TODO: This isn't accurate
            #       "|" is an OR
            #       "," is an AND
            my %depends;
            foreach my $pkg (@pkgs) {
                if ( $pkg =~ /^ ([A-Za-z0-9_.\-]+) \s+ \( ( [^)]+ ) \) $/xms ) {
                    $depends{$1} = $2;
                }
                else {
                    $depends{$pkg} = '';
                }
            }

            $packages{$cur_package}{$name} = \%depends;
        };
    };

    my %actions = (
        'Package' => sub ($name) {
            $packages{$name}{'package'} = $cur_package = $name;
        },

        'Status'               => $take_all_as->('status'),
        'Priority'             => $take_first_as->('priority'),
        'Section'              => $take_first_as->('section'),
        'Installed-Size'       => $take_first_as->('installed_size'),
        'Efi-Vendor'           => $take_joined_as->('efi_vendor'),
        'Ruby-Versions'        => $take_joined_as->('ruby_versions'),
        'Maintainer'           => $take_joined_as->('maintainer'),
        'Architecture'         => $take_first_as->('arch'),
        'Multi-Arch'           => $take_first_as->('multi_arch'),
        'Version'              => $take_first_as->('version'),
        'Essential'            => $take_first_as->('essential'),
        'Important'            => $take_first_as->('important'),
        'Original-Vcs-Browser' => $take_first_as->('original_vcs_browser'),
        'Original-Vcs-Git'     => $take_first_as->('original_vcs_git'),
        'Cnf-Visible-Pkgname'  => $take_first_as->('cnf_visible_pkgname'),
        'Config-Version'       => $take_first_as->('config_version'),
        'Triggers-Pending'     => $take_first_as->('triggers_pending'),
        'Depends'              => $take_deplist_as->('depends'),
        'Pre-Depends'          => $take_deplist_as->('pre_depends'),
        'Recommends'           => $take_deplist_as->('recommends'),
        'Replaces'             => $take_deplist_as->('replaces'),
        'Breaks'               => $take_deplist_as->('breaks'),
        'Enhances'             => $take_deplist_as->('enhances'),
        'Suggests'             => $take_deplist_as->('suggests'),
        'Provides'             => $take_deplist_as->('provides'),
        'Conflicts'            => $take_deplist_as->('conflicts'),
        'Built-Using'          => $take_deplist_as->('built_using'),
        'Description'          => $take_joined_as->('description'),
        'Source'               => $take_joined_as->('source'),
        'Homepage'             => $take_first_as->('homepage'),
        'Original-Maintainer'  => $take_joined_as->('original_maintainer'),

        'Conffiles' => sub (@args) {
            my %conffiles;
            for ( my $i = 0; $i < @args; $i++ ) {
                my $path = $args[$i];
                $conffiles{$path} = { 'hash' => $args[ $i + 1 ] };
                $i++;

                if ( ( $args[ $i + 1 ] // '' ) eq 'obsolete' ) {
                    $conffiles{$path}{'obsolete'} = 1;
                    $i++;
                }
            }

            $packages{$cur_package}{'conffiles'} = \%conffiles;
        },
    );

    my ( $cur_key, @cur_content );
    my $maybe_process_content_cb = sub {

        # Is there any previous content?
        $cur_key and @cur_content
          or return;

        my $cb = $actions{$cur_key}
          or return;

        $cb->(@cur_content);
    };

    chomp( my @lines = split /\n/xms, $string );
    foreach my $line (@lines) {
        if ( $line =~ /^ ([A-Za-z0-9\-]+) : (.+)? $/xms ) {
            my ( $key, $value ) = ( $1, $2 // '' );
            s/^\s+//xms for $key, $value;
            s/\s+$//xms for $key, $value;

            # Process information for previous key
            $maybe_process_content_cb->();

            $cur_key     = $key;
            @cur_content = split /\s+/xms, $value;
        }
        elsif ( substr( $line, 0, 1 ) eq ' ' ) {

            # Multi-line
            push @cur_content, split /\s+/xms, $line =~ s/^\s+//xmsr;
        }
    }

    # End-of-input processing
    $maybe_process_content_cb->();

    return \%packages;
}

sub parse () {
    my $dpkg    = Cpanel::Binaries::Debian::DpkgQuery->new();
    my $content = $dpkg->cmd('--status');
    return parse_string( $content->{'output'} );
}

1;

__END__

=pod

=head1 NAME

C<Cpanel::Parser::DpkgQuery> - Parse the output of C<dpkg> information.

=head1 SYNOPSIS

    use Cpanel::Parser:DpkgQuery ();

    # Run and parse 'dpkg-query --status'
    my $data = Cpanel::Parser::DpkgQuery::parse();

    # Parse a string you get yourself
    my $string = somehow_run_dpkgquery_with_args('--status');
    my $data   = Cpanel::Parser::DpkgQuery::parse_string($string);

=head1 DESCRIPTION

This module parses the output C<dpkg-query --status> and could - if you
adjust the output - parse C<dpkg -I> too. See below for this usage.

It supports the following options:

=over 4

=item * B<Architecture> as C<architecture>

=item * B<Breaks> as C<breaks>

=item * B<Built-Using> as C<built_using>

=item * B<Cnf-Visible-Pkgname> as C<cnf_visible_pkgname>

=item * B<Config-Version> as C<config_version>

=item * B<Conffiles> as C<conffiles>

=item * B<Conflicts> as C<conflicts>

=item * B<Depends> as C<depends>

=item * B<Description> as C<description>

=item * B<Efi-Vendor> as C<efi_vendor>

=item * B<Enhances> as C<enhances>

=item * B<Essential> as C<essential>

=item * B<Homepage> as C<homepage>

=item * B<Important> as C<important>

=item * B<Installed-Size> as C<installed_size>

=item * B<Maintainer> as C<maintainer>

=item * B<Multi-Arch> as C<multi_arch>

=item * B<Original-Maintainer> as C<original_maintainer>

=item * B<Original-Vcs-Browser> as C<original_vcs_browser>

=item * B<Original-Vcs-Git> as C<original_vcs_git>

=item * B<Package> as C<package>

=item * B<Pre-Depends> as C<pre_depends>

=item * B<Priority> as C<priority>

=item * B<Provides> as C<provides>

=item * B<Recommends> as C<recommends>

=item * B<Replaces> as C<replaces>

=item * B<Ruby-Versions> as C<ruby_versions>

=item * B<Section> as C<section>

=item * B<Source> as C<source>

=item * B<Status> as C<status>

=item * B<Suggests> as C<suggests>

=item * B<Triggers-Pending> as C<triggers_pending>

=item * B<Version> as C<version>

=back

It also handles versions in C<depends>, C<pre_depends>, C<recommends>,
C<replaces>, C<breaks>, C<enhances>, C<suggests>, C<provides>,
C<conflicts>, and C<built_using>.

The limitation in dependency lists like those above is that it does not
detect OR conditions. That is, the string C<"= 1.3 | &gt; 1.5"> is not
parsed as either 1.3 or above 1.5. (This can be added if there's a need.)

=head1 FUNCTIONS

=head2 C<parse()>

    my $data = Cpanel::Parser::DpkgQuery::parse();
    # $data = {
    #     'mypackage_1' => {
    #         'package'    => 'mypackage_1',
    #         'maintainer' => 'some person <their@email.com>',
    #         'depends'    => {
    #             'foo' => '= 1.2',
    #             'bar' => '> 3.2',
    #         },
    #         ...
    #     },
    #     'mypackage_2' => {...},
    # };

=head2 C<parse_string($string)>

    my $string = get_value_of_dpkgquery_status();
    my $data   = Cpanel::Parser::DpkgQuery::parse_string($string);

This returns the same as the C<parse()> function.

=head1 Parsing more than C<--stauts>

If you want to parse C<dpkg -I package1 pavkage2...>, you need to
remove the leading space that it creates for all the output.

    my $string       = value_of_dpkg_with_args( '-I', @list_of_packages );
    my $clean_string = $string =~ s/^\s//xmsgr;
    my $data         = Cpanel::Parser::DpkgQuery::parse_string($string);

=head1 SEE ALSO

=over 4

=item * L<Cpanel::Binaries::Debian::DpkgQuery>

Used for calling C<dpkg-query --status>.

=item * L<Dpkg::Control>

This module seems to implement the same thing and should be considered
as a possible replacement to this.

=back

=head1 AUTHOR

Sawyer X
