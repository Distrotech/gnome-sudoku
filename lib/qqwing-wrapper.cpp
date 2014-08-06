/* -*- Mode: C++; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-
 *
 * Copyright © 2014 Parin Porecha
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 2 of the License, or (at your option) any later
 * version. See http://www.gnu.org/copyleft/gpl.html the full text of the
 * license.
 */

#include "qqwing-wrapper.h"

#include <algorithm>
#include <iostream>

#include <glib.h>
#include <qqwing.hpp>

using namespace qqwing;
using namespace std;

/*
 * Generate a symmetric puzzle of specified difficulty.
 */
int* qqwing_generate_puzzle(int difficulty)
{
    int i = 0;
    const int MAX_ITERATIONS = 1000;
    const int BOARD_SIZE = 81;
    SudokuBoard board;

    board.setRecordHistory(true);
    board.setLogHistory(false);
    board.setPrintStyle(SudokuBoard::ONE_LINE);

    for (i = 0; i < MAX_ITERATIONS; i++)
    {
        bool havePuzzle = board.generatePuzzleSymmetry(SudokuBoard::RANDOM);
        board.solve();
        if (havePuzzle && static_cast<SudokuBoard::Difficulty>(difficulty) == board.getDifficulty())
            break;
    }

    if (i == MAX_ITERATIONS)
        g_error("Could not generate puzzle of specified difficulty. I tried so hard. Please report at bugzilla.gnome.org.");

    const int* original = board.getPuzzle();
    int* copy = new int[BOARD_SIZE];
    std::copy(original, &original[BOARD_SIZE], copy);
    return copy;
}

/*
 * Print the stats gathered while solving the puzzle given as input.
 */
void qqwing_print_stats(int* puzzle)
{
    SudokuBoard board;
    board.setRecordHistory(true);
    board.setLogHistory(false);
    board.setPuzzle(puzzle);
    board.solve();

    cout << "Number of Givens: " << board.getGivenCount() << endl;
    cout << "Number of Singles: " << board.getSingleCount() << endl;
    cout << "Number of Hidden Singles: " << board.getHiddenSingleCount() << endl;
    cout << "Number of Naked Pairs: " << board.getNakedPairCount() << endl;
    cout << "Number of Hidden Pairs: " << board.getHiddenPairCount() << endl;
    cout << "Number of Pointing Pairs/Triples: " << board.getPointingPairTripleCount() << endl;
    cout << "Number of Box/Line Intersections: " << board.getBoxLineReductionCount() << endl;
    cout << "Number of Guesses: " << board.getGuessCount() << endl;
    cout << "Number of Backtracks: " << board.getBacktrackCount() << endl;
    cout << "Difficulty: " << board.getDifficultyAsString() << endl;
}
