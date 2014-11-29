package MT::Plugin::Askimet;
use strict;

use vars qw( $VERSION );
$VERSION = '1.2';

use MT::Plugin;
use MT::JunkFilter qw(ABSTAIN);
use MT::Util qw( start_background_task );

my $plugin;
{
    my $desc = <<DESC;
MT-Akismet is the official plugin for Movable Type that transparently integrates its junk handling capabilities with the Akismet collaborative spam filtering service.
DESC
    my $settings = [
                    ['api_key', {Scope => 'system'}],
                    ['weight', {Default => 1, Scope => 'blog'}]
    ];    # ugly. ugly. stuff.
    my $about = {
                 name                   => 'MT-Akismet',
                 description            => $desc,
                 key                    => __PACKAGE__,
                 author_name            => 'Appnel Solutions for Automattic',
                 author_link            => 'http://appnel.com/',
                 plugin_link            => 'http://akismet.com/development/',
                 doc_link               => 'http://appnel.com/docs/mtakismet',
                 version                => $VERSION,
                 blog_config_template   => 'config.tmpl',
                 system_config_template => 'system.tmpl',
                 settings               => MT::PluginSettings->new($settings)
    };
    $plugin = MT::Plugin->new($about);
}
MT->add_plugin($plugin);
MT->add_callback('HandleJunk',    5, $plugin, \&handle_junk);
MT->add_callback('HandleNotJunk', 5, $plugin, \&handle_not_junk);
MT->register_junk_filter({name => 'Akismet', code => \&akismet_score});

#--- plugin handlers

sub handle_junk {
    my ($cb, $app, $thing) = @_;
    require Akismet;
    my $key = is_valid_key($thing)      or return;
    my $sig = package_signature($thing) or return;
    start_background_task(sub { MT::Akismet->submit_spam($sig, $key) });
}

sub handle_not_junk {
    my ($cb, $app, $thing) = @_;
    require Akismet;
    my $key = is_valid_key($thing)      or return;
    my $sig = package_signature($thing) or return;
    start_background_task(sub { MT::Akismet->submit_ham($sig, $key) });
}

sub akismet_score {
    my $thing = shift;
    require Akismet;
    my $key = is_valid_key($thing)      or return ABSTAIN;
    my $sig = package_signature($thing) or return ABSTAIN;
    my $res = MT::Akismet->check($sig, $key);
    return ABSTAIN unless $res && $res->http_response->is_success;
    my $config = $plugin->get_config_hash('blog:' . $thing->blog_id);
    my $weight = $config->{weight};
    my ($score, $grade) = $res->status ? ($weight, 'ham') : (-$weight, 'spam');
    ($score, ["Akismet says $grade"]);
}

#--- utility

sub is_valid_key {
    my $thing = shift;
    my $r     = MT->request;
    unless ($r->stash('MT::Plugin::Askimet::api_key')) {
        my $key = $plugin->get_config_value('api_key') || return;
        $r->stash('MT::Plugin::Askimet::api_key', $key);
    }
    $r->stash('MT::Plugin::Askimet::api_key');
}

sub package_signature {
    my $thing = shift;
    my $sig   = MT::Akismet::Signature->new;
    $sig->user_agent($ENV{HTTP_USER_AGENT});
    $sig->referrer($ENV{HTTP_REFERER});
    $sig->user_ip($thing->ip);
    $sig->blog(cache('B' . $thing->blog_id));
    if (ref $thing eq 'MT::Comment') {
        $sig->permalink(cache($thing->entry_id));
        $sig->comment_type('comment');
        $sig->comment_author($thing->author);
        $sig->comment_author_email($thing->email);
        $sig->comment_author_url($thing->url);
        $sig->comment_content($thing->text);
    } elsif (ref $thing eq 'MT::TBPing') {
        require MT::Trackback;
        my $tb = MT::Trackback->load($thing->tb_id);
        $sig->permalink(cache($tb->entry_id));
        $sig->comment_type('trackback');
        $sig->comment_author($thing->blog_name);
        $sig->comment_author_url($thing->source_url);
        $sig->comment_content(join "\n", $thing->title, $thing->excerpt);
    } else {
        return;    # don't know what this is.
    }
    $sig;
}

sub cache {
    my $id    = shift;
    my $cache = MT->request->stash('MT::Plugin::Askimet::permalinks');
    unless ($cache) {
        $cache = {};
        MT->request->stash('MT::Plugin::Askimet::permalinks', $cache);
    }
    unless ($cache->{$id}) {
        if ($id =~ /^B/) {
            require MT::Blog;
            my $b = MT::Blog->load(substr($id, 1)) or return;
            $cache->{$id} = $b->site_url;
        } else {
            require MT::Entry;
            my $e = MT::Entry->load($id) or return;
            $cache->{$id} = $e->permalink;
        }
    }
    $cache->{$id};
}

1;
