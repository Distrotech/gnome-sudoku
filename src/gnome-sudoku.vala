/* -*- Mode: vala; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

using Gtk;
using Gee;
using Gdk;

public class Sudoku : Gtk.Application
{
    private GLib.Settings settings;
    private Builder builder;

    private ApplicationWindow window;

    // The current game and view, if they exist
    private SudokuGame game;
    private SudokuView view;

    private HeaderBar header_bar;
    private Box game_box; // Holds the grid and controls boxes
    private Box grid_box; // Holds the view

    private Box controls_box; // Holds the controls (including the number picker)
    private NumberPicker number_picker;

    private SudokuStore sudoku_store;

    private SudokuSaver saver;

    private const GLib.ActionEntry action_entries[] =
    {
        {"new-game", new_game_cb                                    },
        {"reset", reset_cb                                          },
        {"undo", undo_cb                                            },
        {"redo", redo_cb                                            },
        {"print", print_cb                                          },
        {"print-multiple", print_multiple_cb                        },
        {"possible-numbers",   possible_numbers_cb,   null, "false" },
        {"unfillable-squares", unfillable_squares_cb, null, "false" },
        {"help", help_cb                                            },
        {"about", about_cb                                          },
        {"quit", quit_cb                                            }
    };

    public Sudoku ()
    {
        Object (application_id: "org.gnome.gnome-sudoku", flags: ApplicationFlags.FLAGS_NONE);
    }

    protected override void startup()
    {
        base.startup ();
        add_action_entries (action_entries, this);
    }

    protected override void activate () {
        settings = new GLib.Settings ("org.gnome.gnome-sudoku");

        builder = new Builder ();
        try
        {
            builder.add_from_resource ("/org/gnome/gnome-sudoku/ui/gnome-sudoku.ui");
            builder.add_from_resource ("/org/gnome/gnome-sudoku/ui/gnome-sudoku-menu.ui");
        }
        catch (GLib.Error e)
        {
            GLib.warning ("Could not load UI: %s", e.message);
        }
        window = (ApplicationWindow) builder.get_object ("sudoku_app");

        add_window (window);

        set_app_menu (builder.get_object ("sudoku-menu") as MenuModel);

        header_bar = (HeaderBar) builder.get_object ("headerbar");
        game_box = (Box) builder.get_object ("game_box");
        grid_box = (Box) builder.get_object ("grid_box");
        controls_box = (Box) builder.get_object ("number_picker_box");

        var undo_button = (Button) builder.get_object ("undo_button");
        undo_button.clicked.connect (() => {
            undo_cb();
        });

        sudoku_store = new SudokuStore ();
        saver = new SudokuSaver ();
        //SudokuGenerator gen = new SudokuGenerator();

        var savegame = saver.get_savedgame ();
        if (savegame != null)
            start_game (savegame.board);
        else
        {
            var random_difficulty = (DifficultyCatagory) Random.int_range (0, 4);
            start_game (sudoku_store.get_random_board (random_difficulty));
        }

        window.show ();

        window.delete_event.connect ((event) => {
            if (!game.board.complete)
                saver.save_game (game);

            return false;
        });
    }

    private void start_game (SudokuBoard board)
    {
        var completed_board = board.clone ();

        var rater = new SudokuRater(ref completed_board);
        var rating = rater.get_difficulty ();
        rating.pretty_print ();
        header_bar.set_subtitle ("%s".printf (rating.get_catagory ().to_string ()));

        var show_possibilities = false;
        var show_warnings = false;

        if (view != null) {
            show_possibilities = view.show_possibilities;
            show_warnings = view.show_warnings;

            grid_box.remove (view);
            controls_box.remove (number_picker);
        }

        game = new SudokuGame (board);

        game.timer.start ();

        view = new SudokuView (game);

        view.show_possibilities = show_possibilities;
        view.show_warnings = show_warnings;

        view.show ();
        grid_box.pack_start (view);

        number_picker = new NumberPicker(ref game.board);
        controls_box.pack_start (number_picker);

        view.cell_focus_in_event.connect ((row, col) => {
            // Only enable the NumberPicker for unfixed cells
            number_picker.sensitive = !game.board.is_fixed[row, col];
        });

        number_picker.number_picked.connect ((number) => {
            view.set_cell_value (view.selected_x, view.selected_y, number);
        });

        game.board.completed.connect (() => {
            view.dance ();

            var time = game.get_total_time_played ();

            for (var i = 0; i < game.board.rows; i++)
            {
                for (var j = 0; j < game.board.cols; j++)
                {
                    view.can_focus = false;
                }
            }

            saver.add_game_to_finished (game, true);

            var dialog = new MessageDialog(window, DialogFlags.DESTROY_WITH_PARENT, MessageType.INFO, ButtonsType.NONE, "Well done, you completed the puzzle in %f seconds", time);

            dialog.add_button ("Same difficulty again", 0);
            dialog.add_button ("New difficulty", 1);

            dialog.response.connect ((response_id) => {
                switch (response_id)
                {
                    case 0:
                        start_game (sudoku_store.get_random_board (rating.get_catagory ()));
                        break;
                    case 1:
                        DifficultyCatagory[] new_range = {};
                        for (var i = 0; i < 4; i++)
                            if (i != (int) rating.get_catagory ())
                                new_range += (DifficultyCatagory) i;

                        start_game (sudoku_store.get_random_board (new_range[Random.int_range (0, 3)]));
                        break;
                }
                dialog.destroy ();
            });

            dialog.show ();
        });
    }

    public void new_game_cb ()
    {
        var random_difficulty = (DifficultyCatagory) Random.int_range (0, 4);
        start_game (sudoku_store.get_random_board (random_difficulty));
    }

    public void reset_cb ()
    {
        game.reset ();
    }

    public void undo_cb ()
    {
        game.undo ();
    }

    public void redo_cb ()
    {
        game.redo ();
    }

    public void print_cb ()
    {
        var printer = new SudokuPrinter ({game.board.clone ()}, ref window);
        printer.print_sudoku ();
    }

    public void print_multiple_cb ()
    {
        var printer = new GamePrinter (sudoku_store, saver, ref window);
        printer.run_dialog ();
    }

    public void possible_numbers_cb (SimpleAction action)
    {
        view.show_possibilities = !view.show_possibilities;
        action.set_state (view.show_possibilities);
    }

    public void unfillable_squares_cb (SimpleAction action)
    {
        view.show_warnings = !view.show_warnings;
        action.set_state (view.show_warnings);
    }

    public void quit_cb ()
    {
        saver.save_game (game);
        window.destroy ();
    }

    public void help_cb ()
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
                                       "John Stowers <john.stowers@gmail.com>",
                                       null };

    public void about_cb ()
    {
        show_about_dialog (window,
                               "program-name", _("Sudoku"),
                               "logo-icon-name", "gnome-sudoku",
                               "version", VERSION,
                               "comments", _("The popular Japanese logic puzzle\n\nGNOME Sudoku is a part of GNOME Games."),
                               "copyright", "Copyright © 2005–2008 Thomas M. Hinkle\nCopyright © 2010–2011 Robert Ancell",
                               "license-type", License.GPL_2_0,
                               "authors", authors,
                               "artists", null,
                               "translator-credits", _("translator-credits"),
                               "website", "https://wiki.gnome.org/Apps/Sudoku/"
                               );
    }
}
