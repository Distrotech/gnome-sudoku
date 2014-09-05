/* -*- Mode: vala; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

using Gtk;
using Gee;
using Gdk;

public class Sudoku : Gtk.Application
{
    private GLib.Settings settings;
    private bool is_maximized;
    private int window_width;
    private int window_height;

    private ApplicationWindow window;

    // The current game and view, if they exist
    private SudokuGame game;
    private SudokuView view;

    private HeaderBar header_bar;
    private Stack main_stack;
    private Box game_box; // Holds the view

    private Box undo_redo_box;
    private Button back_button;

    private SudokuSaver saver;

    private SimpleAction undo_action;
    private SimpleAction redo_action;
    private SimpleAction clear_action;
    private SimpleAction print_action;
    private SimpleAction print_multiple_action;

    private string header_bar_subtitle;

    private bool show_possibilities = false;

    private const GLib.ActionEntry action_entries[] =
    {
        {"new-game", new_game_cb                                    },
        {"start-game", start_game_cb, "i"                           },
        {"reset", reset_cb                                          },
        {"back", back_cb                                            },
        {"undo", undo_cb                                            },
        {"redo", redo_cb                                            },
        {"print", print_cb                                          },
        {"print-multiple", print_multiple_cb                        },
        {"help", help_cb                                            },
        {"about", about_cb                                          },
        {"quit", quit_cb                                            }
    };

    private static const OptionEntry[] option_entries =
    {
        { "version", 'v', 0, OptionArg.NONE, null,
        /* Help string for command line --version flag */
        N_("Show release version"), null},

        { "show-possible-values", 's', 0, OptionArg.NONE, null,
        /* Help string for command line --show-possible flag */
        N_("Show the possible values for each cell"), null},

        { null }
    };

    public Sudoku ()
    {
        Object (application_id: "org.gnome.sudoku", flags: ApplicationFlags.FLAGS_NONE);
        add_main_option_entries (option_entries);
    }

    protected override int handle_local_options (GLib.VariantDict options)
    {
        if (options.contains ("version"))
        {
            /* Not translated so can be easily parsed */
            stderr.printf ("gnome-sudoku %s\n", VERSION);
            return Posix.EXIT_SUCCESS;
        }
        if (options.contains ("show-possible-values"))
            show_possibilities = true;

        /* Activate */
        return -1;
    }

    protected override void startup ()
    {
        base.startup ();

        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (GETTEXT_PACKAGE, LOCALEDIR);
        Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (GETTEXT_PACKAGE);

        add_action_entries (action_entries, this);

        settings = new GLib.Settings ("org.gnome.sudoku");
        var action = settings.create_action ("show-warnings");
        action.notify["state"].connect (() =>
            view.show_warnings = settings.get_boolean ("show-warnings"));
        add_action (action);

        add_accelerator ("<Primary>z", "app.undo", null);
        add_accelerator ("<Primary><Shift>z", "app.redo", null);
        add_accelerator ("<Primary>r", "app.reset", null);
        add_accelerator ("<Primary>n", "app.new-game", null);
        add_accelerator ("<Primary>p", "app.print", null);
        add_accelerator ("<Primary>q", "app.quit", null);
        add_accelerator ("F1", "app.help", null);

        Gtk.Window.set_default_icon_name ("gnome-sudoku");
    }

    protected override void activate () {
        var css_provider = new Gtk.CssProvider ();
        try
        {
            /* Pixel-perfect compatibility with games that have a Button without ButtonBox. */
            var data = """GtkButtonBox { -GtkButtonBox-child-internal-pad-x:0; }
                          GtkBox#start_box { margin:0 80px 0 80px; }""";
            css_provider.load_from_data (data, data.length);
        }
        catch (GLib.Error e)
        {
            warning ("Error loading css styles: %s", e.message);
        }
        Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        var builder = new Builder.from_resource ("/org/gnome/sudoku/ui/gnome-sudoku.ui");

        window = (ApplicationWindow) builder.get_object ("sudoku_app");
        window.configure_event.connect (window_configure_event_cb);
        window.window_state_event.connect (window_state_event_cb);
        window.set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
        if (settings.get_boolean ("window-is-maximized"))
            window.maximize ();

        add_window (window);

        header_bar = (HeaderBar) builder.get_object ("headerbar");
        main_stack = (Stack) builder.get_object ("main_stack");
        game_box = (Box) builder.get_object ("game_box");
        undo_redo_box = (Box) builder.get_object ("undo_redo_box");
        back_button = (Button) builder.get_object ("back_button");

        undo_action = (SimpleAction) lookup_action ("undo");
        redo_action = (SimpleAction) lookup_action ("redo");
        clear_action = (SimpleAction) lookup_action ("reset");
        print_action = (SimpleAction) lookup_action ("print");
        print_multiple_action = (SimpleAction) lookup_action ("print-multiple");

        saver = new SudokuSaver ();
        var savegame = saver.get_savedgame ();
        if (savegame != null)
            start_game (savegame.board);
        else
            show_new_game_screen ();

        window.show ();

        window.delete_event.connect ((event) => {
            if (game != null && !game.board.is_empty () && !game.board.complete)
                saver.save_game (game);

            return false;
        });
    }

    protected override void shutdown ()
    {
        base.shutdown ();

        /* Save window state */
        settings.set_int ("window-width", window_width);
        settings.set_int ("window-height", window_height);
        settings.set_boolean ("window-is-maximized", is_maximized);
    }

    private bool window_configure_event_cb (Gdk.EventConfigure event)
    {
        if (!is_maximized)
        {
            window_width = event.width;
            window_height = event.height;
        }

        return false;
    }

    private bool window_state_event_cb (Gdk.EventWindowState event)
    {
        if ((event.changed_mask & Gdk.WindowState.MAXIMIZED) != 0)
            is_maximized = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;
        return false;
    }

    private void start_game (SudokuBoard board)
    {
        undo_action.set_enabled (false);
        redo_action.set_enabled (false);

        if (view != null)
            game_box.remove (view);

        header_bar_subtitle = board.difficulty_category.to_string ();

        game = new SudokuGame (board);
        back_cb ();

        game.timer.start ();

        view = new SudokuView (game);
        view.set_size_request (480, 480);

        view.show_possibilities = show_possibilities;
        view.show_warnings = settings.get_boolean ("show-warnings");

        view.show ();
        game_box.pack_start (view);

        game.cell_changed.connect (() => {
            undo_action.set_enabled (!game.is_undostack_null ());
            redo_action.set_enabled (!game.is_redostack_null ());
            clear_action.set_enabled (!game.board.is_empty ());
        });

        game.board.completed.connect (() => {
            for (var i = 0; i < game.board.rows; i++)
                for (var j = 0; j < game.board.cols; j++)
                    view.can_focus = false;

            saver.add_game_to_finished (game, true);

            /* Text in dialog that displays when the game is over. */
            var time_str = ngettext ("Well done, you completed the puzzle in %d minute",
                                     "Well done, you completed the puzzle in %d minutes",
                                     int.max (1, (int) game.get_total_time_played () / 60));
            var dialog = new MessageDialog (window, DialogFlags.DESTROY_WITH_PARENT, MessageType.INFO, ButtonsType.NONE, time_str);

            dialog.add_button (_("Same difficulty again"), 0);
            dialog.add_button (_("New difficulty"), 1);

            dialog.response.connect ((response_id) => {
                switch (response_id)
                {
                    case 0:
                        start_game (SudokuGenerator.generate_board (board.difficulty_category));
                        break;
                    case 1:
                        // FIXME - This looks hack-ish
                        DifficultyCategory[] new_range = {};
                        for (var i = 1; i < 5; i++)
                            if (i != (int) board.difficulty_category)
                                new_range += (DifficultyCategory) i;

                        start_game (SudokuGenerator.generate_board (new_range[Random.int_range (0, 3)]));
                        break;
                }
                dialog.destroy ();
            });

            dialog.show ();
        });
    }

    private void show_new_game_screen ()
    {
        main_stack.set_visible_child_name ("start_box");
        clear_action.set_enabled (false);
        back_button.visible = game != null;
        undo_redo_box.visible = false;
        header_bar_subtitle = header_bar.get_subtitle ();
        header_bar.set_subtitle (null);
        print_action.set_enabled (false);
    }

    private void new_game_cb ()
    {
        show_new_game_screen ();
    }

    private void start_game_cb (SimpleAction action, Variant? difficulty)
    {
        // Since we cannot have enums in .ui file, the 'action-target' property
        // of new game buttons in data/gnome-sudoku.ui
        // has been set to integers corresponding to the enums.
        // Following line converts those ints to their DifficultyCategory
        var selected_difficulty = (DifficultyCategory) difficulty.get_int32 ();

        back_button.sensitive = false;

        SudokuGenerator.generate_boards_async.begin (1, selected_difficulty, (obj, res) => {
            try {
                var gen_boards = SudokuGenerator.generate_boards_async.end (res);
                back_button.sensitive = true;
                start_game (gen_boards[0]);
            } catch (ThreadError e) {
                error ("Thread error: %s", e.message);
            }
        });
    }

    private void reset_cb ()
    {
        var dialog = new MessageDialog (window, DialogFlags.MODAL, MessageType.QUESTION, ButtonsType.OK_CANCEL, _("Reset the board to its original state?"));

        dialog.response.connect ((response_id) => {
            if (response_id == ResponseType.OK)
            {
                view.clear ();
                game.reset ();
                undo_action.set_enabled (false);
                redo_action.set_enabled (false);
            }
            dialog.destroy ();
        });

        dialog.show ();
    }

    private void back_cb ()
    {
        main_stack.set_visible_child_name ("frame");
        clear_action.set_enabled (!game.board.is_empty ());
        back_button.visible = false;
        undo_redo_box.visible = true;
        header_bar.set_subtitle (header_bar_subtitle);
        print_action.set_enabled (true);
    }

    private void undo_cb ()
    {
        if (main_stack.get_visible_child_name () != "frame")
            return;
        game.undo ();
        undo_action.set_enabled (!game.is_undostack_null ());
        view.queue_draw ();
    }

    private void redo_cb ()
    {
        if (main_stack.get_visible_child_name () != "frame")
            return;
        game.redo ();
        redo_action.set_enabled (!game.is_redostack_null ());
        view.queue_draw ();
    }

    private void print_cb ()
    {
        if (main_stack.get_visible_child_name () != "frame")
            return;
        print_action.set_enabled (false);
        print_multiple_action.set_enabled (false);
        var printer = new SudokuPrinter ({game.board.clone ()}, ref window);
        printer.print_sudoku ();
        print_action.set_enabled (true);
        print_multiple_action.set_enabled (true);
    }

    private void print_multiple_cb ()
    {
        var printer = new GamePrinter (saver, ref window);
        printer.run_dialog ();
    }

    private void quit_cb ()
    {
        saver.save_game (game);
        window.destroy ();
    }

    private void help_cb ()
    {
        try
        {
            show_uri (window.get_screen (), "help:gnome-sudoku", get_current_event_time ());
        }
        catch (GLib.Error e)
        {
            GLib.warning ("Unable to open help: %s", e.message);
        }
    }

    private const string[] authors = { "Robert Ancell <robert.ancell@gmail.com>",
                                       "Christopher Baines <cbaines8@gmail.com>",
                                       "Thomas M. Hinkle <Thomas_Hinkle@alumni.brown.edu>",
                                       "Parin Porecha <parinporecha@gmail.com>",
                                       "John Stowers <john.stowers@gmail.com>",
                                       null };

    private void about_cb ()
    {
        show_about_dialog (window,
                               "program-name", _("Sudoku"),
                               "logo-icon-name", "gnome-sudoku",
                               "version", VERSION,
                               /* Appears on the About dialog. %s is the version of the QQwing puzzle generator in use. */
                               "comments", _("The popular Japanese logic puzzle\n\nPuzzles generated by QQwing %s".printf (SudokuGenerator.qqwing_version ())),
                               "copyright", "Copyright © 2005–2008 Thomas M. Hinkle\nCopyright © 2010–2011 Robert Ancell\nCopyright © 2014 Parin Porecha",
                               "license-type", License.GPL_2_0,
                               "authors", authors,
                               "artists", null,
                               "translator-credits", _("translator-credits"),
                               "website", "https://wiki.gnome.org/Apps/Sudoku/"
                               );
    }

    public static int main (string[] args)
    {
        return new Sudoku ().run (args);
    }
}
