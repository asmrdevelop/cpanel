package Cpanel::EditHttpdconf;

# cpanel - Cpanel/EditHttpdconf.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Carp;
use File::Spec;

use Cpanel::PwCache                      ();
use Cpanel::SafeFile::RW                 ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::AcctUtils::Owner             ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::HttpUtils::Version           ();
use Cpanel::HttpUtils::ApRestart::BgSafe ();
use Cpanel::FileUtils::Copy              ();
use Cpanel::Path::Normalize              ();
use Cpanel::CPAN::Hash::Merge            ();
use Cpanel::Config::userdata::Guard      ();
use Cpanel::Reseller                     ();
use Cpanel::Logger                       ();
use Cpanel::Rand                         ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::WildcardDomain               ();

sub edit_httpdconf {
    my ( $code_ref, $httpd_conf ) = @_;
    $httpd_conf = apache_paths_facade->file_conf() if !$httpd_conf;
    return if !-e $httpd_conf;
    my $tmp_file = Cpanel::Rand::get_tmp_file_by_name($httpd_conf);    # audit case 46806 ok
    Cpanel::FileUtils::Copy::safecopy( $httpd_conf, $tmp_file );
    chmod oct(600), $tmp_file;
    local $Cpanel::EditHttpdconf::local_flags{'0E0_means_no_changes_were_made'} = 0;
    my $result = Cpanel::SafeFile::RW::safe_readwrite( $httpd_conf, $code_ref );
    chmod oct(600), $httpd_conf;

    # zero-but-true, perldoc Cpanel::SafeFile
    if ( $Cpanel::EditHttpdconf::local_flags{'0E0_means_no_changes_were_made'} && $result && $result eq '0E0' ) {
        unlink $tmp_file;
        return $result;
    }
    else {
        require Cpanel::ConfigFiles::Apache::Syntax;
        my $ref = Cpanel::ConfigFiles::Apache::Syntax::check_syntax();

        if ( $ref->{'status'} ) {
            unlink $tmp_file;
            return 1;
        }
        else {
            Cpanel::Logger::logger(
                {
                    'message'   => "Apache conf failed syntax check: $ref->{'message'}",
                    'level'     => 'warn',
                    'service'   => __PACKAGE__,
                    'output'    => 0,
                    'backtrace' => 1,
                }
            );
            Cpanel::FileUtils::Copy::safecopy( $tmp_file, $httpd_conf );
            unlink $tmp_file;
            return;
        }
    }
}

sub get_owner_vhost_include_path {
    my ( $owner, $inc_name, $type, $apv ) = @_;

    if ( !defined $owner ) {
        carp(q{You must specify the reseller's username});
        return;
    }

    if ( !Cpanel::Reseller::isreseller($owner) && $owner ne 'root' ) {
        carp(q{username is not a reseller or root});
        return;
    }

    if ( !defined $inc_name ) {
        carp(q{You must specify the name of the include});
        return;
    }

    $inc_name = Cpanel::Path::Normalize::normalize($inc_name) // '';
    ($inc_name) = reverse split /\//, $inc_name;
    $inc_name =~ s{[.].*}{} if defined $inc_name;    # remove file extension
    if ( !$inc_name ) {
        carp('invalid filename');
        return;
    }

    $inc_name .= ".owner-$owner";

    if ( defined $type ) {
        if ( $type ne 'std' && $type ne 'ssl' ) {
            carp(q{Invalid type, defaulting to 'std'});
            $type = 'std';
        }
    }

    if ( defined $apv ) {
        if ( $apv ne '1' && $apv ne '2' ) {
            $apv = Cpanel::HttpUtils::Version::get_current_apache_version_key() || 2;
            $apv = 2 if $apv =~ /^2_\d+$/;
            carp(q{Invalid apv, defaulting to current version});

        }

        if ( !defined $type ) {
            carp(q{No type defined, defaulting to 'std'});
            $type = 'std';
        }
    }

    $type = '' if !$type;
    $apv  = '' if !$apv;
    return File::Spec->catfile( _get_conf_base_dir(), $type, $apv, $inc_name );
}

sub ensure_vhost_include_directives {    ## no critic qw(Subroutines::ProhibitExcessComplexity) -- this needs a rewrite
    my ($users_ar) = @_;
    my %user_lookup;
    @user_lookup{ @{$users_ar} } = ();

    Cpanel::AcctUtils::DomainOwner::Tiny::build_domain_cache();

    Cpanel::AcctUtils::Owner::build_trueuserowners_cache();

    my $apver = Cpanel::HttpUtils::Version::get_current_apache_version_key() || 2;
    $apver = 2 if $apver =~ /^2_\d+$/;

    return edit_httpdconf(
        sub {
            my ( $rw_fh, $safe_replace_content_coderef ) = @_;

            my %dash_d_cache = (
                _get_conf_base_dir() . '/'       => '',
                _get_conf_base_dir() . '/std/'   => '',
                _get_conf_base_dir() . '/std/1/' => '',
                _get_conf_base_dir() . '/std/2/' => '',
                _get_conf_base_dir() . '/ssl/'   => '',
                _get_conf_base_dir() . '/ssl/1/' => '',
                _get_conf_base_dir() . '/ssl/2/' => '',
            );

            for my $path ( keys %dash_d_cache ) {
                $dash_d_cache{$path} = -d $path ? 1 : 0;
            }

            my @new_contents;
            my $invhost           = 0;
            my $cur_servername    = '';
            my $cur_username      = '';
            my $is_ssl            = 0;
            my @domains_list      = ();
            my $include_comment   = "    # To customize this VirtualHost use an include file at the following location\n";
            my $skip_next_comment = 0;

            # We're doing some funky () = glob() below to force the globs into list context
            # By default glob will return a scalar which ends up undef on the second iteration of the same glob

          LINE:
            while ( my $line = readline($rw_fh) ) {
                if ( $line !~ m{\s*[#]} ) {
                    if ($invhost) {

                        # do not keep any existing userdata includes
                        if ( $line =~ m{Include .*conf/userdata/.*} ) {
                            if ( $cur_username && exists $user_lookup{$cur_username} ) {
                                next LINE;
                            }
                        }

                        # vhost logic
                        elsif ( $line =~ m{^\s*</VirtualHost}i ) {
                            my $include_found = 0;
                            if ( $cur_servername && $cur_username && exists $user_lookup{$cur_username} ) {
                                my $type               = $is_ssl ? 'ssl' : 'std';
                                my $vhost_include_base = _get_conf_base_dir() . '/';
                                my $owner              = Cpanel::AcctUtils::Owner::getowner($cur_username) || '';

                                if ( $dash_d_cache{$vhost_include_base} ) {
                                    if ( () = glob("$vhost_include_base*.conf") ) {
                                        $include_found = 1;
                                        push @new_contents, qq{    Include "$vhost_include_base*.conf"\n};
                                    }
                                    if ($owner) {
                                        if ( () = glob("$vhost_include_base*.owner-$owner") ) {
                                            $include_found = 1;
                                            push @new_contents, qq{    Include "$vhost_include_base*.owner-$owner"\n};
                                        }
                                    }

                                    $vhost_include_base .= "$type/";
                                    if ( $dash_d_cache{$vhost_include_base} ) {
                                        if ( () = glob("$vhost_include_base*.conf") ) {
                                            $include_found = 1;
                                            push @new_contents, qq{    Include "$vhost_include_base*.conf"\n};
                                        }

                                        if ($owner) {
                                            if ( () = glob("$vhost_include_base*.owner-$owner") ) {
                                                $include_found = 1;
                                                push @new_contents, qq{    Include "$vhost_include_base*.owner-$owner"\n};
                                            }
                                        }

                                        $vhost_include_base .= "$apver/";
                                        if ( $dash_d_cache{$vhost_include_base} ) {
                                            if ( () = glob("$vhost_include_base*.conf") ) {
                                                $include_found = 1;
                                                push @new_contents, qq{    Include "$vhost_include_base*.conf"\n};
                                            }
                                            if ($owner) {
                                                if ( () = glob("$vhost_include_base*.owner-$owner") ) {
                                                    $include_found = 1;
                                                    push @new_contents, qq{    Include "$vhost_include_base*.owner-$owner"\n};
                                                }
                                            }

                                            # caching these stats would probably cause more problems than they solve
                                            if ( -d "$vhost_include_base$cur_username/" ) {
                                                if ( () = glob("$vhost_include_base$cur_username/*.conf") ) {
                                                    $include_found = 1;
                                                    push @new_contents, qq{    Include "$vhost_include_base$cur_username/*.conf"\n};
                                                }

                                                for my $domain ( _uniq( $cur_servername, @domains_list ) ) {

                                                    # directory paths should be wildcard encoded
                                                    $domain = Cpanel::WildcardDomain::encode_wildcard_domain($domain);
                                                    if ( -d "$vhost_include_base$cur_username/$domain/" ) {
                                                        if ( () = glob("$vhost_include_base$cur_username/$domain/*.conf") ) {
                                                            $include_found = 1;
                                                            push @new_contents, qq{    Include "$vhost_include_base$cur_username/$domain/*.conf"\n};
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                unless ($include_found) {

                                    # If no includes exist, add the include comment suggesting the servername vhost include file
                                    push @new_contents, $include_comment;
                                    my $domain = $cur_servername;

                                    # directory paths should be wildcard encoded
                                    $domain = Cpanel::WildcardDomain::encode_wildcard_domain($domain);
                                    push @new_contents, qq{    # Include "$vhost_include_base$cur_username/$domain/*.conf"\n};
                                }
                            }

                            $invhost        = 0;
                            $cur_servername = '';
                            $cur_username   = '';
                            @domains_list   = ();
                        }
                        elsif ( $line =~ m{\s*ServerAlias\s+} ) {
                            my $copy = $line;
                            $copy =~ s{\s*ServerAlias\s+}{};
                            chomp $copy;
                            @domains_list = split /\s+/, $copy;
                        }
                        elsif ( $line =~ m{ServerName\s*(\S+)} ) {
                            $cur_servername = $1;
                            $cur_servername =~ s{ \A www [.] }{}xms;

                            # we need the decoded wildcard servername here to properly look up the owner of the domain
                            my $wildcard_unsafe_servername = Cpanel::WildcardDomain::decode_wildcard_domain($cur_servername);
                            $cur_username = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $wildcard_unsafe_servername, { 'default' => 'nobody' } );
                        }
                    }
                    elsif ( $line =~ m{[<]VirtualHost }i ) {
                        $invhost        = 1;
                        $is_ssl         = ( ( $line =~ m/\:443/i ) ? 1 : 0 );
                        $cur_servername = '';
                        $cur_username   = '';
                        @domains_list   = ();
                    }
                }
                elsif ( $invhost && $cur_servername && $cur_username && exists $user_lookup{$cur_username} && $line =~ /\Q$include_comment\E/ ) {
                    $skip_next_comment = 1;
                    next LINE;
                }
                elsif ($skip_next_comment) {
                    $skip_next_comment = 0;
                    next LINE;
                }

                push @new_contents, $line;
            }

            return "Edited by ensure_vhost_include_directives() - $0"
              if $safe_replace_content_coderef->( $rw_fh, \@new_contents );
            return;
        }
    );
}

sub add_vhost_include {    ## no critic qw(Subroutines::ProhibitExcessComplexity) -- this needs a rewrite
    my ($args_hr) = @_;
    my $args_ok = _get_valid_vhost_include_hr_from_args_hr($args_hr) or return;

  ATYPE:
    for my $type ( sort keys %{ $args_ok->{'content'} } ) {
        if ( !exists $args_ok->{'_files'}{$type} ) {
            carp 'type does not exist';
            next ATYPE;
        }

      AVER:
        for my $ver ( sort keys %{ $args_ok->{'content'}{$type} } ) {
            if ( !exists $args_ok->{'_files'}{$type}{$ver} ) {
                carp 'version does not exist in type';
                next AVER;
            }

            my $path = $args_ok->{'_files'}{$type}{$ver};
            if ( $args_hr->{'fail_if_exists'} && -e $path ) {
                carp qq{'$path' already exists}, return;
            }
            else {
                my $content = $args_ok->{'content'}{$type}{$ver};

                if ( ref $content eq 'CODE' ) {
                    my @my_args = ref $args_ok->{'content_coderef_args'} eq 'ARRAY' ? @{ $args_ok->{'content_coderef_args'} } : ();
                    $content = $content->( $args_ok->{'user'}, $args_ok->{'domain'}, $path, @my_args );
                }

                if ( open my $fh, '>', $path ) {
                    print {$fh} $content;
                    close $fh;

                    my $uid   = $args_ok->{'owner'} ? Cpanel::PwCache::getpwnam( $args_ok->{'owner'} ) : 0;
                    my $gid   = $args_ok->{'group'} ? getgrnam( $args_ok->{'group'} )                  : 0;
                    my $owner = $uid                || 0;        # ??? root or getpwnam( $args_ok->{'user'} );
                    my $group = $gid                || 0;        # ??? root or getgrnam( $args_ok->{'user'} );
                    my $chmod = $args_ok->{'chmod'} || '0640';

                    chown $owner, $group, $path
                      or carp("Could not chown $owner, $group, $path: $!");
                    chmod oct($chmod), $path
                      or carp("Could not chmod $chmod, $path: $!");
                }
                else {
                    carp qq{Could not open '$path': $!};
                }
            }
        }
    }

    #
    # If this is called from ensure_vhost_includes, we are probably
    # reading the value from the file below so there is no
    # good reason to set it to the same value we just read
    #
    unless ( $args_hr->{'skip_userdata_update'} ) {
        if ( $args_ok->{'domain'} ) {
            my $guard     = Cpanel::Config::userdata::Guard->new( $args_ok->{'user'}, $args_ok->{'domain'} );
            my $hr        = $guard->data();
            my $new_value = $args_ok->{'userdata_true_value'} || 1;
            if ( !exists $hr->{ $args_ok->{'file'} } || $hr->{ $args_ok->{'file'} } ne $new_value ) {
                $hr->{ $args_ok->{'file'} } = $new_value;
                $guard->save();

                # No need to update the cache as the file argument is not in it
                # Cpanel::Config::userdata::UpdateCache::update( $args_ok->{'user'} );
            }
        }
        else {
            my $guard     = Cpanel::Config::userdata::Guard->new( $args_ok->{'user'} );
            my $hr        = $guard->data();
            my $new_value = $args_ok->{'userdata_true_value'} || 1;
            if ( !exists $hr->{ $args_ok->{'file'} } || $hr->{ $args_ok->{'file'} } ne $new_value ) {
                $hr->{ $args_ok->{'file'} } = $new_value;
                $guard->save();

                # No need to update the cache as the file argument is not in it
                # Cpanel::Config::userdata::UpdateCache::update( $args_ok->{'user'} );
            }
        }
    }

    ensure_vhost_include_directives( [ $args_ok->{'user'} ] ) if !defined $args_ok->{'ensure_vhost_include_directives'} || $args_ok->{'ensure_vhost_include_directives'};
    Cpanel::HttpUtils::ApRestart::BgSafe::restart()           if $args_hr->{'restart_apache'};

    return 1;
}

sub del_vhost_include {
    my ($args_hr) = @_;
    local $args_hr->{'skip_mkpath'} = 1;
    my $args_ok = _get_valid_vhost_include_hr_from_args_hr($args_hr) or return;

  BTYPE:
    for my $type ( sort keys %{ $args_ok->{'_files'} } ) {
        next BTYPE if $args_ok->{'skip_type'}{$type};

      BVER:
        for my $ver ( sort keys %{ $args_ok->{'_files'}{$type} } ) {
            next BVER if $args_ok->{'skip_vers'}{$type}{$ver};

            my $file = $args_ok->{'_files'}{$type}{$ver};
            if ( -e $file ) {
                unlink $file or carp qq{'$file' could not be removed: $!};
            }
            else {
                carp qq{'$file' does not exist}, return
                  if $args_ok->{'fail_if_not_exists'};
            }
        }
    }

    #
    # If this is called from ensure_vhost_includes, we are probably
    # reading the value from the file below so there is no
    # good reason to set it to the same value we just read
    #
    unless ( $args_hr->{'skip_userdata_update'} ) {
        if ( $args_ok->{'domain'} ) {
            my $guard = Cpanel::Config::userdata::Guard->new( $args_ok->{'user'}, $args_ok->{'domain'} );
            my $hr    = $guard->data();
            if ( exists $hr->{ $args_ok->{'file'} } && $hr->{ $args_ok->{'file'} } != 0 ) {
                $hr->{ $args_ok->{'file'} } = 0;
                $guard->save();

                # No need to update the cache as the file argument is not in it
                # Cpanel::Config::userdata::UpdateCache::update( $args_ok->{'user'} );
            }
        }
        else {
            my $guard = Cpanel::Config::userdata::Guard->new( $args_ok->{'user'} );
            my $hr    = $guard->data();
            if ( exists $hr->{ $args_ok->{'file'} } && $hr->{ $args_ok->{'file'} } != 0 ) {
                $hr->{ $args_ok->{'file'} } = 0;
                $guard->save();

                # No need to update the cache as the file argument is not in it
                # Cpanel::Config::userdata::UpdateCache::update( $args_ok->{'user'} );
            }
        }
    }

    ensure_vhost_include_directives( [ $args_ok->{'user'} ] ) if !defined $args_ok->{'ensure_vhost_include_directives'} || $args_ok->{'ensure_vhost_include_directives'};
    Cpanel::HttpUtils::ApRestart::BgSafe::restart()           if $args_hr->{'restart_apache'};

    return 1;
}

sub _get_valid_vhost_include_hr_from_args_hr {
    my ($args_hr) = @_;

    # return hashref of good values or carp, return

    carp(q{need to specify 'file' key}), return if !$args_hr->{'file'};

    if ( !$args_hr->{'user'} && !$args_hr->{'domain'} ) {
        carp('need to specify either user or domain'), return;
    }

    my $args_ok = {};

    if ( exists $args_hr->{'user'} ) {
        carp('invalid user'), return
          if $args_hr->{'user'} eq 'root' || !Cpanel::PwCache::getpwnam( $args_hr->{'user'} );
    }

    $args_ok->{'user'} = $args_hr->{'user'};

    if ( $args_hr->{'domain'} ) {
        $args_ok->{'user'} = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $args_hr->{'domain'} );
    }

    carp('Could not find owner of domain'), return if !$args_ok->{'user'};

    $args_ok->{'file'} = Cpanel::Path::Normalize::normalize( $args_ok->{'file'} );
    ( $args_ok->{'file'} ) = reverse split /\//, $args_hr->{'file'};
    carp('invalid filename'), return if !$args_ok->{'file'};

    my $base = _get_conf_base_dir();    # NO trailing slash
    my $sub  = $args_ok->{'user'};
    if ( $args_hr->{'domain'} ) {
        my $safe_domain = $args_hr->{'domain'};

        # directory paths should be wildcard encoded
        $safe_domain = Cpanel::WildcardDomain::encode_wildcard_domain($safe_domain);
        $sub .= '/' . $safe_domain;
    }

    if ( !$args_hr->{'skip_mkpath'} ) {
        my %mode_map = (
            "$base/std/1/$sub/" => $args_ok->{'mkpath_mode'}{'std'}{'1'},
            "$base/std/2/$sub/" => $args_ok->{'mkpath_mode'}{'std'}{'2'},
            "$base/ssl/1/$sub/" => $args_ok->{'mkpath_mode'}{'ssl'}{'1'},
            "$base/ssl/2/$sub/" => $args_ok->{'mkpath_mode'}{'ssl'}{'2'},
        );

        while ( my ( $path, $mode ) = each %mode_map ) {
            Cpanel::SafeDir::MK::safemkdir( $path, $mode )
              or carp "Could not safemkdir( $path, $mode ): $!";
        }
    }

    $args_ok->{'_files'} = {
        'std' => {
            '1' => "$base/std/1/$sub/$args_ok->{'file'}",
            '2' => "$base/std/2/$sub/$args_ok->{'file'}",
        },
        'ssl' => {
            '1' => "$base/ssl/1/$sub/$args_ok->{'file'}",
            '2' => "$base/ssl/2/$sub/$args_ok->{'file'}",
        },
    };

    Cpanel::CPAN::Hash::Merge::set_behavior('RIGHT_PRECEDENT');
    return Cpanel::CPAN::Hash::Merge::merge( $args_hr, $args_ok );
}

sub get_hashref_of_domains_with_vhost_include {
    my ( $file, $apv, $users_in_question_ar ) = @_;

    if ( !defined $file ) {
        carp('No file specified'), $! = 22, return;
    }
    my $lookup = {};

    # $apv = '..TODO..' if !$apv;
    # $users_in_question_ar = '..TODO..'
    #     if !defined $users_in_question_ar || ref $users_in_question_ar ne 'ARRAY';

  USER:
    for my $user ( @{$users_in_question_ar} ) {
      TYPE:
        for my $type (qw(std ssl)) {
            my $base = _get_conf_base_dir() . "/$type/$apv/$user";
            next TYPE if !-d $base;

            my @domains;
            if ( opendir my $base_dh, $base ) {
                @domains = grep !/ \A [.]+ \z /xms, readdir($base_dh);
                close $base_dh;
            }
            else {
                carp "Could not readdir '$base': $!";
            }

          DOM:
            for my $dom (@domains) {
                if ( -e _get_conf_base_dir() . "/$type/$apv/$user/$dom/$file" ) {
                    $lookup->{$dom} = 1;
                    next DOM;
                }
            }
        }
    }

    return $lookup;
}

sub rebuild_httpd_conf {
    my ($line_handler) = @_;

    if ( ref $line_handler ne 'CODE' ) {
        $line_handler = sub {
            my ($line) = @_;
            return $line;    # Cpanel::SafeRun::Dynamic::livesaferun() prints whatever is returned
        };
    }

    if ( -x '/usr/local/cpanel/scripts/rebuildhttpdconf' ) {
        require Cpanel::SafeRun::Dynamic;
        Cpanel::SafeRun::Dynamic::livesaferun(
            'prog'      => ['/usr/local/cpanel/scripts/rebuildhttpdconf'],
            'formatter' => $line_handler,
        );
        return 1;
    }
    else {
        return;
    }
}

sub _uniq {
    my %tmp = map { $_ => 1 } @_;
    return keys %tmp;
}

sub _get_conf_base_dir {
    return apache_paths_facade->dir_conf_userdata();
}

1;

__END__

=head1 edit_httpdconf

    if (edit_httpdconf(\&httpdconf_fixer)) {
        print "Great success!";
    }

Wrapper around SafeOpen::safe_readwrite() that

=over 4

=item * defaults to actual httpd.conf if no file is given.

=item * does the httpd.conf syntax check afterwards

If your code ref returns 0E0  then the rcs record is skipped like normal.

If you want to also skip the syntax check simply set $Cpanel::EditHttpdconf::local_flags{'0E0_means_no_changes_were_made'} to true in your coderef before you return "0E0".

A localized $Cpanel::EditHttpdconf::local_flags{'0E0_means_no_changes_were_made'} is created just before your editing coderef is called.

=back

=head1 vhost_include

my $rc = [add|del]_vhost_include({
    'user'    => 'username', # not needed if you specify domain
    'domain'  => 'domain.com', # Optional "specific domain entry", user is changed to the owner of this domain if specified
    'file'    => 'cp_whatever.conf',
    'restart_apache' => 1, # Optional, default is '0' can be left out
    'ensure_vhost_include_directives' => 0, # Optional, default is '1' can be left out
# add_ only:
    'content' => {
        'std' => {
            '1' => 'file content || coderef that returns file contents given ($user, $domain, $path, @content_coderef_args)',
            '2' => 'file content',
        },
        'ssl' => {
            '1' => 'file content'
            '2' => 'file content',
        },
    },
    # Optional:
    'userdata_true_value' => 'whatever', # whatever true value makes sense instead of '1' that can be used by /usr/local/cpanel/scripts/ensure_vhost_includes
    'chown' => '0644', # default 0640 ( or 0600 ??? )
    'owner' => 'bob',  # default is 'root' ( or 'user' key ??? )
    'group' => 'tech', # default is 'root' ( or 'user key's group ??? )
    'content_coderef_args'  => [], # args to pass last to 'content' coderefs if any
    'fail_if_exists'        => 1, #  default is '0' can be left out
    'skip_mkpath'           => 1, # default is '0' can be left out
    'mkpath_mode'           => { # assumgin we're not skip_mkpath these shoucl be 3 or 4 digit mode to pass to safemkdir()
        'std' => {
            '1' => 640,
            '2' => 640,
        },
        'ssl' => {
            '1' => 600,
            '2' => 600,
        },
    },
# del_ only:
    'fail_if_not_exists'    => 1, # default is '0' can be left out
    # Optional skip
    'skip_type'             => {
         'std' => 1,
         'ssl' => 0,
    },
    'skip_vers'             => {
        'std' => {
            '1' => 0,
            '2' => 1,
        },
        'ssl' => {
            '1' => 0,
            '2' => 1,
        },
     },
});

my $path = get_owner_vhost_include_path( $owner, $inc_name[, $type, $apv] ) || die;
# write, unlink, etc as you wish
$type can be 'std', or 'ssl'
$apv can be '1' or '2'
if you specify them and they are invalid they default to 'std' and 'crruent version' respectively
