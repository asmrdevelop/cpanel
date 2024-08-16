package Cpanel::ConfigFiles::Apache;

# cpanel - Cpanel/ConfigFiles/Apache.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::ConfigFiles::Apache - Manages config file locations for Apache

=head1 SYNOPSIS

    use Cpanel::ConfigFiles::Apache ();

    my $httpdbase = $apacheconf->dir_base();
    my $httpdconf = $apacheconf->file_conf();

or

    use Cpanel::ConfigFiles::Apache 'apache_paths_facade'; # see POD for import specifics

    sub foo {
        print "httpd lives at: " . apache_paths_facade->bin_httpd() . "\n";
        …

=head1 DESCRIPTION

This module gives a configurable place to find all Apache-related
configuration files and binary paths.  Previously, all such values
were hard-coded in the cPanel codebase, and made any sort of change
prohibitive.

The object functions as a multiton, intended to make it possible to
have an old configuration object and a new configuration object active
at once.  When migrating from EasyApache3 to an RPM-based system, this
will be necessary.

=cut

use cPstrict;

use Cpanel::Config::LoadConfig ();

my $multiton = {};

=head1 METHODS

Only the new() method can take any arguments.  Arguments passed to any
of the accessor methods will be ignored.

=head2 B<new($path)>

Retrieve the singleton which corresponds with the supplied path argument.

=over 4

=item B<$path> [in, optional]

Optional argument which specifies the configuration file pathname.
Default is to use /etc/cpanel/ea4/paths.conf.

=back

B<Returns:>  A reference to a blessed singleton object.

=cut

sub apache_paths_facade {
    state $lazyfacade = Cpanel::ConfigFiles::Apache->new();
    return $lazyfacade;
}

=head2 B<is_installed()>

Check if apache is set. Returns a boolean if set.

=cut

sub is_installed ($self) {

    # allow the two syntaxes: class method & function
    $self = apache_paths_facade() unless ref $self;
    return -e $self->bin_httpd;
}

# We import() so that its use can be use/require/compiled/uncompiled safe (see https://cpanel.wiki/x/CY0tAg for details).
#
# We could instead have consumers be require() and use() safe w/ uncompiled and perlcc’d code by having them each:
#     BEGIN { *apache_paths_facade = \&Cpanel::Config::LoadConfig::apache_paths_facade; }
# or
#     sub apache_paths_facade { goto &Cpanel::Config::LoadConfig::apache_paths_facade; } # or redefine …
# etc
#
sub import ( $class, @args ) {

    if ( scalar @args ) {
        if ( grep { $_ eq 'apache_paths_facade' } @args ) {
            my $caller = caller;
            no strict 'refs';
            *{ $caller . "::apache_paths_facade" } = \&apache_paths_facade;
        }
        else {
            die "$class does not import @args\n";
        }
    }

    return 1;
}

use constant EA4_PATHS_PATH => '/etc/cpanel/ea4/paths.conf';

sub new ( $class, $path = undef ) {

    $path //= EA4_PATHS_PATH;

    my $mtime = ( stat($path) )[9] // 0;
    return $multiton->{$path} if defined $multiton->{$path} && $multiton->{$path}{'_meta'}{'mtime'} == $mtime;

    my $self = exists $multiton->{$path} ? $multiton->{$path} : {};
    $self->{_meta}{path}  = $path;
    $self->{_meta}{mtime} = $mtime;

    # defaults
    $self->{'dir_base'}             = '/usr/local/apache';
    $self->{'dir_logs'}             = $self->{'dir_base'} . '/logs';
    $self->{'dir_domlogs'}          = $self->{'dir_base'} . '/domlogs';
    $self->{'dir_modules'}          = $self->{'dir_base'} . '/modules';
    $self->{'dir_run'}              = $self->{'dir_logs'};
    $self->{'dir_conf'}             = $self->{'dir_base'} . '/conf';
    $self->{'dir_conf_includes'}    = $self->{'dir_conf'} . '/includes';
    $self->{'dir_conf_userdata'}    = $self->{'dir_conf'} . '/userdata';
    $self->{'dir_docroot'}          = $self->{'dir_base'} . '/htdocs';
    $self->{'file_access_log'}      = $self->{'dir_logs'} . '/access_log';
    $self->{'file_error_log'}       = $self->{'dir_logs'} . '/error_log';
    $self->{'file_conf'}            = $self->{'dir_conf'} . '/httpd.conf';
    $self->{'file_conf_mime_types'} = $self->{'dir_conf'} . '/mime.types';
    $self->{'file_conf_srm_conf'}   = $self->{'dir_conf'} . '/srm.conf';
    $self->{'file_conf_php_conf'}   = $self->{'dir_conf'} . '/php.conf';
    $self->{'bin_httpd'}            = $self->{'dir_base'} . '/bin/httpd';
    $self->{'bin_apachectl'}        = $self->{'dir_base'} . '/bin/apachectl';
    $self->{'bin_suexec'}           = $self->{'dir_base'} . '/bin/suexec';

    # actuals
    my $conf;
    if ($mtime) {
        $conf = Cpanel::Config::LoadConfig::loadConfig( $path, undef, '\s*=\s*', undef, '^\s*', undef, { 'empty_is_invalid' => 1 } );
    }
    $conf ||= {};
    foreach my $key ( keys %$conf ) {
        my $value = $conf->{$key};

        # only set the key if it is one we set above in the defaults
        if ( defined $value && length($value) && exists $self->{$key} ) {
            $self->{$key} = $value;
        }
    }

    if ( !exists $multiton->{$path} ) {
        $multiton->{$path} = bless $self, $class;
    }

    return $multiton->{$path};
}

=head2 B<get_template_hashref()>

Returns a hashref of all the configured paths, for purposes of feeding
into a teplate rendering function.  The returned hashref is a copy of
the hash in our multiton, in the case that a caller decides to try
changing the contents.

=cut

sub get_template_hashref ($self) {
    my %newhash = %$self;
    delete $newhash{_meta};
    return \%newhash;
}

=head2 B<dir_base()>

Returns the base directory of the Apache installation.

=cut

sub dir_base ($self) {
    return $self->{'dir_base'};
}

=head2 B<dir_logs()>

Returns the logs directory of the Apache installation.

=cut

sub dir_logs ($self) {
    return $self->{'dir_logs'};
}

=head2 B<dir_domlogs()>

Returns the directory which contains the per-domain access logs for
the Apache installation.

=cut

sub dir_domlogs ($self) {
    return $self->{'dir_domlogs'};
}

=head2 B<dir_base()>

Returns the directory which contains the loadable modules for the
Apache installation.

=cut

sub dir_modules ($self) {
    return $self->{'dir_modules'};
}

=head2 B<dir_run()>

Returns the run directory of the Apache installation.  This will
contain lock files, pid files, and related runtime-specific files.

=cut

sub dir_run ($self) {
    return $self->{'dir_run'};
}

=head2 B<dir_conf()>

Returns the configuration directory of the Apache installation.  This
may be different from the directory which contains the httpd.conf file
(accessed with B<file_conf()> below).

=cut

sub dir_conf ($self) {
    return $self->{'dir_conf'};
}

=head2 B<dir_conf_includes()>

Returns the cPanel configuration includes directory for the Apache
installation.

=cut

sub dir_conf_includes ($self) {
    return $self->{'dir_conf_includes'};
}

=head2 B<dir_conf_userdata()>

Returns the cPanel user includes directory for the Apache
installation.

=cut

sub dir_conf_userdata ($self) {
    return $self->{'dir_conf_userdata'};
}

=head2 B<dir_docroot()>

Returns the directory which contains the server document root for the
Apache installation.

=cut

sub dir_docroot ($self) {
    return $self->{'dir_docroot'};
}

=head2 B<file_access_log()>

Returns the path of the top-level server access log for the Apache
installation.

=cut

sub file_access_log ($self) {
    return $self->{'file_access_log'};
}

=head2 B<file_error_log()>

Returns the path of the error log for the Apache installation.

=cut

sub file_error_log ($self) {
    return $self->{'file_error_log'};
}

=head2 B<file_conf()>

Returns the path of the httpd.conf file for the Apache installation.

=cut

sub file_conf ($self) {
    return $self->{'file_conf'};
}

=head2 B<file_conf_mime_types()>

Returns the path of the mime.types file for the Apache installation.

=cut

sub file_conf_mime_types ($self) {
    return $self->{'file_conf_mime_types'};
}

=head2 B<file_conf_srm_conf()>

Returns the path of the srm.conf file the Apache installation.  This
file is mostly deprecated, so this file may or may not actually exist.

=cut

sub file_conf_srm_conf ($self) {
    return $self->{'file_conf_srm_conf'};
}

=head2 B<file_conf_php_conf()>

Returns the path of the php.conf file for the Apache installation.

=cut

sub file_conf_php_conf ($self) {
    return $self->{'file_conf_php_conf'};
}

=head2 B<bin_httpd()>

Returns the path of the httpd binary for the Apache installation.

=cut

sub bin_httpd ($self) {
    return $self->{'bin_httpd'};
}

=head2 B<bin_apachectl()>

Returns the path of the apachectl binary for the Apache installation.

=cut

sub bin_apachectl ($self) {
    return $self->{'bin_apachectl'};
}

=head2 B<bin_suexec()>

Returns the path of the suexec binary for the Apache installation.

=cut

sub bin_suexec ($self) {
    return $self->{'bin_suexec'};
}

=head1 FUNCTIONS

=head2 apache_paths_facade()

Exportable helper façade to avoid the need for a package global and the compile issues with those.

We import() so that its use can be use/require/compiled/uncompiled safe (see https://cpanel.wiki/x/CY0tAg for details).

Since we need to avoid creating obects at compile time, using this saves a lot of headache.

    use Cpanel::ConfigFiles::Apache 'apache_paths_facade'; # see POD for import specifics

    sub foo {
        print "httpd lives at: " . apache_paths_facade->bin_httpd() . "\n";
        …

=cut

sub _clear_cache {
    $multiton = {};
    return;
}

1;
