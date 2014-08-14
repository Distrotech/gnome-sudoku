/* -*- Mode: vala; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

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
        SourceFunc callback = generate_boards_async.callback;
        var boards = new SudokuBoard[nboards];

        // Hold reference to closure to keep it from being freed whilst
        // thread is active.
        ThreadFunc<void*> generate = () => {
            for (var i = 0; i < nboards; i++)
                boards[i] = generate_board (category);

            // Schedule callback
            Idle.add((owned) callback);
            return null;
        };
        new Thread<void*>("Generator thread", generate);

        // Wait for background thread to schedule our callback
        yield;
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
