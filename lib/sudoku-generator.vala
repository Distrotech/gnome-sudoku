/* -*- Mode: vala; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

using Gee;

public class SudokuGenerator : Object
{
    private SudokuGenerator () {
    }

    public static SudokuBoard generate_board (DifficultyCategory category)
    {
        var board = new SudokuBoard ();
        int[] puzzle = QQwing.generate_puzzle ((int) category);

        for (var row = 0; row < board.rows; row++)
            for (var col = 0; col < board.cols; col++)
            {
                var val = puzzle[(row * board.cols) + col];
                if (val != 0)
                    board.insert (row, col, val, true);
            }
        board.difficulty_category = category;

        return board;
    }

    public async static SudokuBoard[] generate_boards_async (int nboards, DifficultyCategory category) throws ThreadError
    {
        var boards_list = new ArrayList<SudokuBoard> ();
        var boards = new SudokuBoard[nboards];

//        var sysinfo = GLibtop.glibtop_sysinfo.get_sysinfo ();
//        stdout.printf ("ncpus = %d\n", sysinfo.ncpu);
        var ncpu = 4;
        var nthreads = int.min (ncpu, nboards);
        var base_nsudokus_each = nboards / nthreads;
        var remainder = nboards % nthreads;
        var nsudokus_per_thread = base_nsudokus_each;

        stdout.printf ("no. of threads = %d\n", nthreads);

        for (var i = 0; i < nthreads; i++)
        {
            if (i > (nthreads - remainder - 1))
                nsudokus_per_thread = base_nsudokus_each + 1;
            var gen_thread = new GeneratorThread (nsudokus_per_thread, category, ref boards_list, generate_boards_async.callback, i);
            Thread<int> thread = new Thread<int> ("Generator thread", gen_thread.run);

            // Relinquish the CPU, so that the generated thread can run
            yield;

            stdout.printf ("waiting for #%d to join\n", i);
            var result = thread.join ();
            stdout.printf ("Thread #%d exited\n", result);
        }

        stdout.printf ("boards list size = %d\n", boards_list.size);
        for (var i = 0; i < boards_list.size; i++)
            boards[i] = boards_list[i];

        return boards;
    }

    public static void print_stats (SudokuBoard board)
    {
        var cells = board.get_cells ();
        var puzzle = new int[board.rows * board.cols];

        for (var row = 0; row < board.rows; row++)
            for (var col = 0; col < board.cols; col++)
                puzzle[(row * board.cols) + col] = cells[row, col];

        QQwing.print_stats (puzzle);
    }

    public static string qqwing_version ()
    {
        return QQwing.get_version ();
    }
}

public class GeneratorThread : Object
{
    private int nsudokus;
    private DifficultyCategory level;
    private int id;
    private ArrayList<SudokuBoard> boards_list;
    private SourceFunc callback;

    public GeneratorThread (int nsudokus, DifficultyCategory level, ref ArrayList<SudokuBoard> boards_list, SourceFunc callback, int id)
    {
        this.nsudokus = nsudokus;
        this.level = level;
        this.id = id;
        this.boards_list = boards_list;
        this.callback = callback;
    }

    public int run ()
    {
        stdout.printf ("generating %d puzzles\n", nsudokus);
        for (var i = 0; i < nsudokus; i++)
            boards_list.add (SudokuGenerator.generate_board (level));

        Idle.add((owned) callback);
        return id;
    }
}
